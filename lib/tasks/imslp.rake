namespace :imslp do
  desc "Import priority composers first (Bach, Beethoven, Mozart, etc.)"
  task priority_sync: :environment do
    puts "Importing priority composers..."
    importer = ImslpImporter.new(resume: true)
    importer.import_priority!
  end

  desc "Reset priority import progress"
  task reset_priority: :environment do
    AppSetting.set("imslp_priority_completed", [])
    puts "Priority import progress reset."
  end

  desc "Sync all scores from IMSLP (runs synchronously). Use resume=true to skip existing."
  task :sync, [:resume, :start_offset] => :environment do |_t, args|
    resume = args[:resume] == "true" || args[:resume] == "1"
    start_offset = (args[:start_offset] || 0).to_i

    puts "Starting IMSLP sync..."
    puts "NOTE: IMSLP has ~500,000+ works. This will take a VERY long time."
    puts "Consider using imslp:enqueue for background processing."
    puts ""

    importer = ImslpImporter.new(resume: resume, start_offset: start_offset)
    importer.import!
  end

  desc "Sync a sample of IMSLP scores. Use imslp:sample[100] for limit, imslp:sample[100,1000] to start at offset 1000"
  task :sample, [:limit, :start_offset] => :environment do |_t, args|
    limit = (args[:limit] || 100).to_i
    start_offset = args[:start_offset]&.to_i || load_progress

    puts "Syncing #{limit} IMSLP scores starting at offset #{start_offset}..."
    puts ""

    importer = ImslpImporter.new(limit: limit, start_offset: start_offset)
    result = importer.import!

    # Save progress for next run
    next_offset = start_offset + limit
    save_progress(next_offset)
    puts ""
    puts "Progress saved. Next run will start at offset #{next_offset}"
    puts "To continue: bin/rails \"imslp:sample[#{limit}]\""
  end

  def load_progress
    Rails.cache.fetch("imslp_import_offset") { 0 }
  end

  def save_progress(offset)
    Rails.cache.write("imslp_import_offset", offset, expires_in: 30.days)
  end

  desc "Show current import progress"
  task progress: :environment do
    offset = load_progress
    total_scores = Score.from_imslp.count
    puts "IMSLP Import Progress"
    puts "  Next offset: #{offset}"
    puts "  Scores imported: #{total_scores}"
    puts ""
    puts "To continue: bin/rails \"imslp:sample[1000]\""
    puts "To reset:    bin/rails imslp:reset_progress"
  end

  desc "Reset import progress to start from beginning"
  task reset_progress: :environment do
    Rails.cache.delete("imslp_import_offset")
    puts "Progress reset. Next import will start from offset 0."
  end

  desc "Queue a background job to sync IMSLP scores"
  task :enqueue, [:start_offset] => :environment do |_t, args|
    start_offset = (args[:start_offset] || load_progress).to_i

    puts "Enqueueing IMSLP sync job (offset: #{start_offset})..."
    ImslpSyncJob.perform_later(resume: true, start_offset: start_offset)
    puts "Job enqueued! Run `bin/jobs` to process the queue."
  end

  desc "Clear all IMSLP scores from database"
  task clear: :environment do
    count = Score.from_imslp.count
    print "This will delete #{count} IMSLP scores. Continue? (y/N) "
    confirm = $stdin.gets.chomp.downcase

    if confirm == "y"
      Score.from_imslp.delete_all
      puts "Deleted #{count} IMSLP scores."
    else
      puts "Aborted."
    end
  end

  desc "Show IMSLP sync statistics"
  task stats: :environment do
    total = Score.from_imslp.count
    puts "IMSLP Scores: #{total}"
    puts ""

    if total > 0
      puts "By composer (top 10):"
      Score.from_imslp
        .group(:composer)
        .order("count_all DESC")
        .limit(10)
        .count
        .each { |composer, count| puts "  #{composer || 'Unknown'}: #{count}" }

      puts ""
      puts "By style/genre (top 10):"
      Score.from_imslp
        .where.not(genres: [nil, ""])
        .pluck(:genres)
        .flat_map { |g| g.split("-") }
        .tally
        .sort_by { |_, v| -v }
        .first(10)
        .each { |genre, count| puts "  #{genre}: #{count}" }

      puts ""
      puts "Files available:"
      puts "  With PDF: #{Score.from_imslp.where.not(pdf_path: [nil, '']).count}"
      puts "  With MusicXML: #{Score.from_imslp.where.not(mxl_path: [nil, '']).count}"
      puts "  With MIDI: #{Score.from_imslp.where.not(mid_path: [nil, '']).count}"

      puts ""
      puts "Last synced: #{Score.from_imslp.maximum(:updated_at)}"

      with_thumbnails = Score.from_imslp.joins(:thumbnail_image_attachment).count
      with_previews = Score.from_imslp.joins(:preview_image_attachment).count
      puts ""
      puts "Thumbnails: #{with_thumbnails} / #{total} (#{(with_thumbnails.to_f / total * 100).round(1)}%)"
      puts "Previews:   #{with_previews} / #{total} (#{(with_previews.to_f / total * 100).round(1)}%)"
    end
  end

  desc "Test IMSLP API connectivity"
  task test_api: :environment do
    require "net/http"
    require "json"

    puts "Testing IMSLP API connectivity..."

    # Test worklist API
    puts ""
    puts "1. Testing Worklist API..."
    uri = URI("https://imslp.org/imslpscripts/API.ISCR.php?account=worklist/disclaimer=accepted/sort=id/type=2/start=0/retformat=json")
    response = Net::HTTP.get_response(uri)

    if response.is_a?(Net::HTTPSuccess)
      data = JSON.parse(response.body)
      work_count = data.reject { |k, _| k == "metadata" }.size
      more = data.dig("metadata", "moreresultsavailable")
      puts "   [OK] Returned #{work_count} works, more available: #{more}"
    else
      puts "   [FAIL] HTTP #{response.code}"
    end

    # Test MediaWiki API
    puts ""
    puts "2. Testing MediaWiki API..."
    uri = URI("https://imslp.org/api.php?action=parse&page=Symphony_No.5,_Op.67_(Beethoven,_Ludwig_van)&prop=wikitext&format=json")
    response = Net::HTTP.get_response(uri)

    if response.is_a?(Net::HTTPSuccess)
      data = JSON.parse(response.body)
      title = data.dig("parse", "title")
      puts "   [OK] Retrieved page: #{title}"
    else
      puts "   [FAIL] HTTP #{response.code}"
    end

    puts ""
    puts "API test complete."
  end

  desc "Generate thumbnails for IMSLP scores"
  task :generate_thumbnails, [:limit] => :environment do |_t, args|
    limit = args[:limit]&.to_i

    scores = Score.from_imslp
                  .where.not(pdf_path: [nil, ''])
                  .left_joins(:thumbnail_image_attachment)
                  .where(active_storage_attachments: { id: nil })

    scores = scores.limit(limit) if limit

    total = scores.count
    puts "Generating thumbnails for #{total} IMSLP scores..."
    puts ""

    success_count = 0
    failed_count = 0

    scores.each_with_index do |score, index|
      print "  [#{index + 1}/#{total}] #{score.title}... "

      generator = ThumbnailGenerator.new(score)
      if generator.generate!
        print "[OK]\n"
        success_count += 1
      else
        print "[FAIL] (#{generator.errors.first})\n"
        failed_count += 1
      end

      sleep(0.5) if score.external?
    end

    puts ""
    puts "Done! Success: #{success_count}, Failed: #{failed_count}"
  end

  desc "Queue background jobs to generate thumbnails for IMSLP scores"
  task :enqueue_thumbnails, [:limit] => :environment do |_t, args|
    limit = args[:limit]&.to_i

    scores = Score.from_imslp
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

  desc "Generate previews for IMSLP scores"
  task :generate_previews, [:limit] => :environment do |_t, args|
    limit = args[:limit]&.to_i

    scores = Score.from_imslp
                  .where.not(pdf_path: [nil, ''])
                  .left_joins(:preview_image_attachment)
                  .where(active_storage_attachments: { id: nil })

    scores = scores.limit(limit) if limit

    total = scores.count
    puts "Generating previews for #{total} IMSLP scores..."
    puts ""

    success_count = 0
    failed_count = 0

    scores.each_with_index do |score, index|
      print "  [#{index + 1}/#{total}] #{score.title}... "

      generator = ThumbnailGenerator.new(score)
      if generator.generate_preview!
        print "[OK]\n"
        success_count += 1
      else
        print "[FAIL] (#{generator.errors.first})\n"
        failed_count += 1
      end

      sleep(0.5) if score.external?
    end

    puts ""
    puts "Done! Success: #{success_count}, Failed: #{failed_count}"
  end

  desc "Queue background jobs to generate previews for IMSLP scores"
  task :enqueue_previews, [:limit] => :environment do |_t, args|
    limit = args[:limit]&.to_i

    scores = Score.from_imslp
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
