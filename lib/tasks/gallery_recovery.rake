# frozen_string_literal: true

namespace :gallery do
  desc "Recover ScorePages from orphaned attachments"
  task recover: :environment do
    puts "=" * 60
    puts "Gallery Recovery"
    puts "=" * 60

    existing_score_ids = Score.pluck(:id).to_set
    existing_pages = ScorePage.pluck(:score_id, :page_number).to_set

    # ScorePages that already have an attachment - don't relink to these
    pages_with_attachments = ActiveStorage::Attachment
      .where(record_type: "ScorePage", name: "image", record_id: ScorePage.select(:id))
      .pluck(:record_id)
      .to_set
    pages_needing_attachment = ScorePage.where.not(id: pages_with_attachments).pluck(:score_id, :page_number).to_set

    orphaned = ActiveRecord::Base.connection.execute(<<-SQL).to_a
      SELECT asa.id, asa.blob_id, asb.filename, asb.byte_size
      FROM active_storage_attachments asa
      JOIN active_storage_blobs asb ON asa.blob_id = asb.id
      WHERE asa.record_type = 'ScorePage'
        AND asa.record_id NOT IN (SELECT id FROM score_pages)
      ORDER BY asb.byte_size DESC
    SQL

    puts "Found #{orphaned.size} orphaned attachments"

    to_create = {}      # key => attachment_id (single, largest file)
    to_relink = {}      # key => attachment_id (single, largest file)
    duplicates = []     # attachment_ids to delete (extras)
    skipped = 0

    orphaned.each do |row|
      filename = row["filename"]
      unless filename =~ /^(\d+)_page_(\d+)\.webp$/
        skipped += 1
        next
      end

      score_id = $1.to_i
      page_num = $2.to_i
      key = [score_id, page_num]

      unless existing_score_ids.include?(score_id)
        skipped += 1
        next
      end

      if existing_pages.include?(key)
        # ScorePage exists
        if pages_needing_attachment.include?(key)
          # ScorePage has no attachment - relink one
          if to_relink.key?(key)
            duplicates << row["id"]
          else
            to_relink[key] = row["id"]
          end
        else
          # ScorePage already has attachment - this is a duplicate
          duplicates << row["id"]
        end
      else
        # Need new ScorePage - pick largest file (ordered by byte_size DESC)
        if to_create.key?(key)
          duplicates << row["id"]
        else
          to_create[key] = row["id"]
        end
      end
    end

    puts "\nAnalysis:"
    puts "  ScorePages to create: #{to_create.size}"
    puts "  Attachments to relink: #{to_relink.size}"
    puts "  Duplicate attachments to delete: #{duplicates.size}"
    puts "  Skipped (Score deleted or bad filename): #{skipped}"

    if to_create.empty? && to_relink.empty?
      puts "\nNothing to recover."
      next
    end

    print "\nProceed? (y/N): "
    unless $stdin.gets&.strip&.downcase == "y"
      puts "Aborted."
      next
    end

    ActiveRecord::Base.transaction do
      # 1. Create new ScorePages
      if to_create.any?
        puts "\nCreating #{to_create.size} ScorePages..."
        now = Time.current
        new_pages = to_create.keys.map do |score_id, page_num|
          { score_id: score_id, page_number: page_num, created_at: now, updated_at: now }
        end
        ScorePage.insert_all(new_pages)
      end

      # 2. Build lookup
      page_lookup = ScorePage.pluck(:score_id, :page_number, :id)
                             .each_with_object({}) { |(sid, pn, id), h| h[[sid, pn]] = id }

      # 3. Relink attachments
      all_updates = []
      to_create.each { |key, aid| all_updates << [aid, page_lookup[key]] }
      to_relink.each { |key, aid| all_updates << [aid, page_lookup[key]] }

      puts "Relinking #{all_updates.size} attachments..."
      all_updates.each_slice(1000).with_index do |batch, i|
        cases = batch.map { |aid, spid| "WHEN #{aid} THEN #{spid}" }.join(" ")
        ids = batch.map(&:first).join(",")
        ActiveRecord::Base.connection.execute(<<-SQL)
          UPDATE active_storage_attachments
          SET record_id = CASE id #{cases} END
          WHERE id IN (#{ids})
        SQL
        print "\r  #{[(i + 1) * 1000, all_updates.size].min}/#{all_updates.size}"
      end
      puts

      # 4. Delete duplicate attachments
      if duplicates.any?
        puts "Deleting #{duplicates.size} duplicate attachments..."
        ActiveStorage::Attachment.where(id: duplicates).delete_all
      end
    end

    puts "\nDone!"
    puts "  ScorePages now: #{ScorePage.count}"
    puts "  Scores with galleries: #{Score.joins(:score_pages).distinct.count}"
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

    # Purge ALL unattached blobs
    unattached_blobs = ActiveStorage::Blob.where.not(id: ActiveStorage::Attachment.select(:blob_id))
    total = unattached_blobs.count

    puts "Purging #{total} blobs from R2..."
    unattached_blobs.find_each.with_index do |blob, i|
      blob.purge
      print "\r  #{i + 1}/#{total}" if (i + 1) % 100 == 0
    end

    puts "\n\nDone!"
    puts "  Blobs remaining: #{ActiveStorage::Blob.count}"
  end
end
