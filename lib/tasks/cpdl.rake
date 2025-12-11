namespace :cpdl do
  desc "Sync all scores from CPDL (runs synchronously). Use resume=true to skip already-imported scores."
  task :sync, [:resume] => :environment do |_t, args|
    resume = args[:resume] == "true" || args[:resume] == "1"
    puts "Starting CPDL sync..."
    puts "This may take a while (CPDL has ~40,000 scores)"
    puts ""

    importer = CpdlImporter.new(resume: resume)
    importer.import!
  end

  desc "Sync a sample of CPDL scores (100 by default). Use resume=true to skip existing."
  task :sample, [:limit, :resume] => :environment do |_t, args|
    limit = (args[:limit] || 100).to_i
    resume = args[:resume] == "true" || args[:resume] == "1"
    puts "Syncing #{limit} CPDL scores..."
    puts ""

    importer = CpdlImporter.new(limit: limit, resume: resume)
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

      with_thumbnails = Score.from_cpdl.joins(:thumbnail_image_attachment).count
      with_previews = Score.from_cpdl.joins(:preview_image_attachment).count
      puts ""
      puts "Thumbnails: #{with_thumbnails} / #{total} (#{(with_thumbnails.to_f / total * 100).round(1)}%)"
      puts "Previews:   #{with_previews} / #{total} (#{(with_previews.to_f / total * 100).round(1)}%)"
    end
  end

  desc "Generate thumbnails for CPDL scores"
  task :generate_thumbnails, [:limit] => :environment do |_t, args|
    limit = args[:limit]&.to_i

    # Find CPDL scores with PDFs but no thumbnails
    scores = Score.from_cpdl
                  .where.not(pdf_path: [nil, ''])
                  .left_joins(:thumbnail_image_attachment)
                  .where(active_storage_attachments: { id: nil })

    scores = scores.limit(limit) if limit

    total = scores.count
    puts "Generating thumbnails for #{total} CPDL scores..."
    puts ""

    success_count = 0
    failed_count = 0

    scores.each_with_index do |score, index|
      print "  [#{index + 1}/#{total}] #{score.title}... "

      generator = ThumbnailGenerator.new(score)
      if generator.generate!
        print "✓\n"
        success_count += 1
      else
        print "✗ (#{generator.errors.first})\n"
        failed_count += 1
      end

      # Be nice to external servers
      sleep(0.5) if score.external?
    end

    puts ""
    puts "Done! Success: #{success_count}, Failed: #{failed_count}"
  end

  desc "Queue background jobs to generate thumbnails for CPDL scores"
  task :enqueue_thumbnails, [:limit] => :environment do |_t, args|
    limit = args[:limit]&.to_i

    scores = Score.from_cpdl
                  .where.not(pdf_path: [nil, ''])
                  .left_joins(:thumbnail_image_attachment)
                  .where(active_storage_attachments: { id: nil })

    scores = scores.limit(limit) if limit

    total = scores.count
    puts "Enqueueing #{total} thumbnail generation jobs..."

    scores.each do |score|
      GenerateThumbnailJob.perform_later(score.id)
    end

    puts "Done! Run job queue to process."
  end

  desc "Generate previews for CPDL scores"
  task :generate_previews, [:limit] => :environment do |_t, args|
    limit = args[:limit]&.to_i

    scores = Score.from_cpdl
                  .where.not(pdf_path: [nil, ''])
                  .left_joins(:preview_image_attachment)
                  .where(active_storage_attachments: { id: nil })

    scores = scores.limit(limit) if limit

    total = scores.count
    puts "Generating previews for #{total} CPDL scores..."
    puts ""

    success_count = 0
    failed_count = 0

    scores.each_with_index do |score, index|
      print "  [#{index + 1}/#{total}] #{score.title}... "

      generator = ThumbnailGenerator.new(score)
      if generator.generate_preview!
        print "✓\n"
        success_count += 1
      else
        print "✗ (#{generator.errors.first})\n"
        failed_count += 1
      end

      sleep(0.5) if score.external?
    end

    puts ""
    puts "Done! Success: #{success_count}, Failed: #{failed_count}"
  end

  desc "Queue background jobs to generate previews for CPDL scores"
  task :enqueue_previews, [:limit] => :environment do |_t, args|
    limit = args[:limit]&.to_i

    scores = Score.from_cpdl
                  .where.not(pdf_path: [nil, ''])
                  .left_joins(:preview_image_attachment)
                  .where(active_storage_attachments: { id: nil })

    scores = scores.limit(limit) if limit

    total = scores.count
    puts "Enqueueing #{total} preview generation jobs..."

    scores.each do |score|
      GeneratePreviewJob.perform_later(score.id)
    end

    puts "Done! Run job queue to process."
  end
end
