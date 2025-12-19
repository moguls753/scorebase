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
end
