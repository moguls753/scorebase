namespace :cpdl do
  desc "Sync all scores from CPDL (runs synchronously)"
  task sync: :environment do
    puts "Starting CPDL sync..."
    puts "This may take a while (CPDL has ~40,000 scores)"
    puts ""

    importer = CpdlImporter.new
    importer.import!
  end

  desc "Sync a sample of CPDL scores (100 by default)"
  task :sample, [:limit] => :environment do |_t, args|
    limit = (args[:limit] || 100).to_i
    puts "Syncing #{limit} CPDL scores..."
    puts ""

    importer = CpdlImporter.new(limit: limit)
    importer.import!
  end

  desc "Queue a background job to sync CPDL scores"
  task enqueue: :environment do
    puts "Enqueueing CPDL sync job..."
    CpdlSyncJob.perform_later
    puts "Job enqueued! Run `bin/jobs` to process the queue."
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
    end
  end
end
