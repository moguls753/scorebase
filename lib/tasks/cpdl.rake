namespace :cpdl do
  desc "Sync all scores from CPDL (runs synchronously). Existing scores are never overwritten."
  task sync: :environment do
    puts "Starting CPDL sync..."
    puts "This may take a while (CPDL has ~40,000 scores)"
    puts ""

    CpdlImporter.new.import!
  end

  desc "Sync a sample of CPDL scores (100 by default)."
  task :sample, [:limit] => :environment do |_t, args|
    limit = (args[:limit] || 100).to_i
    puts "Syncing #{limit} CPDL scores..."
    puts ""

    CpdlImporter.new(limit: limit).import!
  end

  desc "Clear all CPDL scores from database"
  task clear: :environment do
    count = Score.from_cpdl.count
    print "This will delete #{count} CPDL scores. Continue? (y/N) "
    confirm = $stdin.gets.chomp.downcase

    if confirm == "y"
      Score.from_cpdl.delete_all
      puts "Deleted #{count} CPDL scores."
    else
      puts "Aborted."
    end
  end

  desc "Show CPDL sync statistics"
  task stats: :environment do
    total = Score.from_cpdl.count
    puts "CPDL Scores: #{total}"
    puts ""

    if total > 0
      puts "By composer (top 10):"
      Score.from_cpdl
        .group(:composer)
        .order("count_all DESC")
        .limit(10)
        .count
        .each { |composer, count| puts "  #{composer || 'Unknown'}: #{count}" }

      puts ""
      puts "Last synced: #{Score.from_cpdl.maximum(:updated_at)}"

      with_thumbnails = Score.from_cpdl.joins(:thumbnail_image_attachment).count
      puts ""
      puts "Thumbnails: #{with_thumbnails} / #{total} (#{(with_thumbnails.to_f / total * 100).round(1)}%)"
    end
  end

  # NOTE: Thumbnail/preview generation tasks moved to images.rake
  # Use: bin/rails images:thumbnails[cpdl] or images:enqueue_thumbnails[cpdl]

  desc "Recover data on empty CPDL rows via patched importer. " \
       "ENV: DRY_RUN=true|false (default true), SHARDS=N (default 3), LIMIT=N (optional)"
  task recover_empty: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    shards  = ENV.fetch("SHARDS", "3").to_i
    limit   = ENV["LIMIT"]&.to_i

    if dry_run
      n = CpdlRecoveryJob.new.send(:scope).count
      puts "DRY_RUN: would process #{n} rows across #{shards} shard(s)"
      puts "Set DRY_RUN=false to enqueue."
      next
    end

    shards.times { |i| CpdlRecoveryJob.perform_later(shard: i, of: shards, limit: limit) }
    puts "Enqueued #{shards} shard(s)" + (limit ? " (limit=#{limit} per shard)" : "")
  end

  desc "Print a sample of CPDL stub candidates (rag_failure_reason=cpdl_stub) for manual inspection."
  task :stub_sample, [:limit] => :environment do |_t, args|
    limit = (args[:limit] || 10).to_i
    rows = Score.where(source: "cpdl", rag_failure_reason: "cpdl_stub").order("RANDOM()").limit(limit)

    puts "Sampling #{rows.size} of #{Score.where(source: 'cpdl', rag_failure_reason: 'cpdl_stub').count} stub candidates:"
    rows.each do |s|
      puts "  ##{s.id}  #{s.title.to_s.truncate(60)}  #{s.external_url}"
    end
  end

  desc "Hard-delete CPDL stub-marker rows (rag_failure_reason=cpdl_stub). " \
       "ENV: DRY_RUN=true|false (default true). Aborts if any have Active Storage attachments."
  task delete_stubs: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    scope = Score.where(source: "cpdl", rag_status: "failed", rag_failure_reason: "cpdl_stub")

    count = scope.count
    if count.zero?
      puts "No stub rows to delete."
      next
    end

    with_attachments = scope.joins(:pdf_file_attachment).count
    if with_attachments.positive?
      abort "#{with_attachments} stub rows have Active Storage attachments. " \
            "Use destroy_all (slower) instead of delete_all, or investigate first."
    end

    if dry_run
      puts "DRY_RUN: would delete #{count} cpdl_stub rows"
      puts "Set DRY_RUN=false to apply."
      next
    end

    deleted = scope.delete_all
    puts "Deleted #{deleted} cpdl_stub rows"
  end
end
