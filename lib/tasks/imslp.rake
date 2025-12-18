namespace :imslp do
  desc "Import priority composers first (Bach, Beethoven, Mozart, etc.)"
  task priority_sync: :environment do
    puts "Importing priority composers..."
    ImslpImporter.new.import_priority!
  end

  desc "Sync all scores from IMSLP (runs synchronously). Existing scores are never overwritten."
  task :sync, [:start_offset] => :environment do |_t, args|
    start_offset = (args[:start_offset] || 0).to_i

    puts "Starting IMSLP sync..."
    puts "NOTE: IMSLP has ~500,000+ works. This will take a VERY long time."
    puts ""

    ImslpImporter.new(start_offset: start_offset).import!
  end

  desc "Sync a sample of IMSLP scores. Use imslp:sample[100] for limit, imslp:sample[100,1000] to start at offset 1000"
  task :sample, [:limit, :start_offset] => :environment do |_t, args|
    limit = (args[:limit] || 100).to_i
    start_offset = args[:start_offset]&.to_i || load_progress

    puts "Syncing #{limit} IMSLP scores starting at offset #{start_offset}..."
    puts ""

    result = ImslpImporter.new(limit: limit, start_offset: start_offset).import!

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
      puts ""
      puts "Thumbnails: #{with_thumbnails} / #{total} (#{(with_thumbnails.to_f / total * 100).round(1)}%)"
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

  # NOTE: Thumbnail/preview generation tasks moved to images.rake
  # Use: bin/rails images:thumbnails[imslp] or images:enqueue_thumbnails[imslp]
end
