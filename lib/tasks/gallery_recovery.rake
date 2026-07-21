# frozen_string_literal: true

namespace :gallery do
  desc "Recover ScorePages from orphaned attachments (batched, resumable, memory-bounded)"
  task recover: :environment do
    conn = ActiveRecord::Base.connection
    batch = (ENV["BATCH"] || 5000).to_i
    dry_run = ENV["DRY_RUN"].present?

    # Orphan = a ScorePage image whose owning score_pages row is gone (the 2026-05-17
    # migration cascade wiped every row; the blobs survived). record_id points nowhere.
    orphaned_where = "asa.record_type = 'ScorePage' AND asa.record_id NOT IN (SELECT id FROM score_pages)"

    puts "=" * 60
    puts "Gallery Recovery (batch=#{batch}#{dry_run ? ', DRY_RUN' : ''})"
    puts "=" * 60

    total = conn.select_value("SELECT COUNT(*) FROM active_storage_attachments asa WHERE #{orphaned_where}").to_i
    puts "Orphaned ScorePage attachments: #{total}"

    if total.zero?
      puts "Nothing to recover."
      next
    end

    if dry_run
      keepers = conn.select_value(<<~SQL).to_i
        SELECT COUNT(DISTINCT asb.filename)
        FROM active_storage_attachments asa
        JOIN active_storage_blobs asb ON asb.id = asa.blob_id
        WHERE #{orphaned_where}
      SQL
      puts "DRY_RUN — would keep ~#{keepers} pages and delete ~#{total - keepers} duplicate attachments. No writes."
      next
    end

    # Phase A — collapse duplicates: keep the largest attachment per filename, delete the rest.
    # Chunked DELETE so a single statement is never unbounded.
    dupes = 0
    loop do
      n = conn.exec_delete(<<~SQL)
        DELETE FROM active_storage_attachments
        WHERE id IN (
          SELECT id FROM (
            SELECT asa.id,
                   ROW_NUMBER() OVER (PARTITION BY asb.filename ORDER BY asb.byte_size DESC, asa.id) AS rn
            FROM active_storage_attachments asa
            JOIN active_storage_blobs asb ON asb.id = asa.blob_id
            WHERE #{orphaned_where}
          ) WHERE rn > 1
          LIMIT #{batch}
        )
      SQL
      dupes += n
      print "\r  deduped: #{dupes}"
      break if n.zero?
    end
    puts

    # Phase B — recreate ScorePages and relink their attachment. Page by attachment id so
    # skipped rows (bad filename / deleted score) advance the cursor and can't loop forever;
    # commit per batch so an interruption loses only the current batch and a rerun resumes.
    created = relinked = skipped = 0
    last_id = 0
    loop do
      rows = conn.select_all(<<~SQL).to_a
        SELECT asa.id AS att_id, asb.filename AS filename
        FROM active_storage_attachments asa
        JOIN active_storage_blobs asb ON asb.id = asa.blob_id
        WHERE #{orphaned_where} AND asa.id > #{last_id}
        ORDER BY asa.id
        LIMIT #{batch}
      SQL
      break if rows.empty?
      last_id = rows.last["att_id"]

      parsed = rows.filter_map do |r|
        m = r["filename"].to_s.match(/\A(\d+)_page_(\d+)\.webp\z/)
        next (skipped += 1) && nil unless m

        { att_id: r["att_id"], score_id: m[1].to_i, page: m[2].to_i }
      end
      next if parsed.empty?

      live = Score.where(id: parsed.map { |p| p[:score_id] }.uniq).pluck(:id).to_set
      valid = parsed.select { |p| live.include?(p[:score_id]) }
      skipped += parsed.size - valid.size
      next if valid.empty?

      ActiveRecord::Base.transaction do
        keys = valid.map { |p| [ p[:score_id], p[:page] ] }.uniq
        lookup = ScorePage.where(score_id: keys.map(&:first).uniq)
                          .pluck(:score_id, :page_number, :id)
                          .each_with_object({}) { |(sid, pg, id), h| h[[ sid, pg ]] = id }

        to_create = keys.reject { |k| lookup.key?(k) }
        if to_create.any?
          now = Time.current
          ScorePage.insert_all(to_create.map { |sid, pg| { score_id: sid, page_number: pg, created_at: now, updated_at: now } })
          ScorePage.where(score_id: to_create.map(&:first).uniq)
                   .pluck(:score_id, :page_number, :id)
                   .each { |sid, pg, id| lookup[[ sid, pg ]] = id }
          created += to_create.size
        end

        # A page that already carries an image keeps it; the orphan for that page is redundant.
        attached = ActiveStorage::Attachment
                   .where(record_type: "ScorePage", name: "image", record_id: lookup.values)
                   .pluck(:record_id).to_set

        relink = []
        drop = []
        valid.each do |p|
          pid = lookup[[ p[:score_id], p[:page] ]]
          if pid && !attached.include?(pid)
            relink << [ p[:att_id], pid ]
            attached << pid
          else
            drop << p[:att_id]
          end
        end

        relink.each_slice(1000) do |slice|
          cases = slice.map { |aid, pid| "WHEN #{aid} THEN #{pid}" }.join(" ")
          ids = slice.map(&:first).join(",")
          conn.execute("UPDATE active_storage_attachments SET record_id = CASE id #{cases} END WHERE id IN (#{ids})")
        end
        ActiveStorage::Attachment.where(id: drop).delete_all if drop.any?
        relinked += relink.size
      end

      print "\r  recovered: #{relinked} pages (#{created} new score_pages)"
    end
    puts

    puts "\nDone!"
    puts "  score_pages now:       #{ScorePage.count}"
    puts "  scores with galleries: #{Score.joins(:score_pages).distinct.count}"
    puts "  duplicates deleted:    #{dupes}"
    puts "  skipped (deleted score / bad filename): #{skipped}"
  end

  desc "Delete orphaned attachments and purge ALL unattached blobs from R2"
  task cleanup: :environment do
    # 1. Orphaned attachments (for deleted Scores)
    orphaned_attachments = ActiveRecord::Base.connection.execute(<<-SQL).to_a
      SELECT id FROM active_storage_attachments
      WHERE record_type = 'ScorePage'
        AND record_id NOT IN (SELECT id FROM score_pages)
    SQL

    # 2. Unattached blobs (duplicates from recovery + will increase after step 1)
    unattached_count = ActiveStorage::Blob.where.not(id: ActiveStorage::Attachment.select(:blob_id)).count

    puts "Found:"
    puts "  #{orphaned_attachments.size} orphaned attachments"
    puts "  #{unattached_count} unattached blobs on R2"

    if orphaned_attachments.empty? && unattached_count == 0
      puts "\nNothing to clean up."
      next
    end

    print "\nProceed with cleanup? (y/N): "
    unless $stdin.gets&.strip&.downcase == "y"
      puts "Aborted."
      next
    end

    # Delete orphaned attachments
    if orphaned_attachments.any?
      puts "\nDeleting #{orphaned_attachments.size} attachments..."
      ActiveStorage::Attachment.where(id: orphaned_attachments.map { |r| r["id"] }).delete_all
    end

    # Batch purge unattached blobs from R2 (1000 at a time)
    unattached_blobs = ActiveStorage::Blob.where.not(id: ActiveStorage::Attachment.select(:blob_id))
    total = unattached_blobs.count

    puts "Purging #{total} blobs from R2 (batch mode)..."

    service = ActiveStorage::Blob.service
    deleted = 0

    unattached_blobs.in_batches(of: 1000) do |batch|
      keys = batch.pluck(:key)

      # Batch delete from R2/S3
      if service.respond_to?(:bucket)
        # S3-compatible: use bucket.delete_objects
        service.bucket.delete_objects(
          delete: { objects: keys.map { |k| { key: k } } }
        )
      else
        # Fallback (Disk): delete individually
        keys.each { |key| service.delete(key) rescue nil }
      end

      # Delete blob records from database
      batch.delete_all

      deleted += keys.size
      puts "  #{deleted}/#{total} purged"
    end

    puts "\nDone!"
    puts "  Blobs remaining: #{ActiveStorage::Blob.count}"
  end
end
