namespace :pdmx do
  desc "Import PDMX scores into database"
  task import: :environment do
    # Parse command line options
    limit = ENV["LIMIT"]&.to_i
    subset = ENV["SUBSET"] || "no_license_conflict"

    puts "=" * 80
    puts "PDMX Import Task"
    puts "=" * 80

    # Check if PDMX exists
    unless Pdmx.exists?
      puts Pdmx.setup_instructions
      exit 1
    end

    # Confirm before import
    existing_count = Score.count
    if existing_count > 0
      puts "\n⚠️  WARNING: Database already contains #{existing_count} scores"
      print "Continue? This will add more scores. (y/N): "
      response = STDIN.gets.chomp
      exit unless response.downcase == "y"
    end

    # Run import
    importer = PdmxImporter.new(limit: limit, subset: subset)
    importer.import!

    puts "\n✅ Done! Total scores in database: #{Score.count}"
  end

  desc "Import a small sample of PDMX scores (for testing)"
  task sample: :environment do
    ENV["LIMIT"] = "100"
    Rake::Task["pdmx:import"].invoke
  end

  desc "Clear all scores from database"
  task clear: :environment do
    count = Score.count
    print "⚠️  Delete all #{count} scores? (y/N): "
    response = STDIN.gets.chomp

    if response.downcase == "y"
      Score.delete_all
      puts "✅ Deleted #{count} scores"
    else
      puts "Cancelled"
    end
  end

  desc "Show PDMX import statistics"
  task stats: :environment do
    puts "=" * 80
    puts "PDMX Statistics"
    puts "=" * 80
    puts "Total scores: #{Score.count}"
    puts "With key signature: #{Score.where.not(key_signature: nil).count}"
    puts "With time signature: #{Score.where.not(time_signature: nil).count}"
    puts "With thumbnails: #{Score.from_pdmx.joins(:thumbnail_image_attachment).count}"
    puts "With previews: #{Score.from_pdmx.joins(:preview_image_attachment).count}"
    puts "With MXL files: #{Score.where.not(mxl_path: nil).where.not(mxl_path: 'N/A').count}"
    puts "\nTop 5 keys:"
    Score.group(:key_signature).order("count_all DESC").limit(5).count.each do |key, count|
      puts "  #{key}: #{count}"
    end
    puts "\nTop 5 time signatures:"
    Score.group(:time_signature).order("count_all DESC").limit(5).count.each do |time, count|
      puts "  #{time}: #{count}"
    end
  end

  desc "Download MuseScore thumbnails from metadata and attach to Active Storage"
  task :download_thumbnails, [:limit] => :environment do |_t, args|
    require "net/http"
    require "json"

    limit = args[:limit]&.to_i

    # Find PDMX scores without thumbnails
    scores = Score.from_pdmx
                  .where.not(metadata_path: [nil, "", "N/A"])
                  .left_joins(:thumbnail_image_attachment)
                  .where(active_storage_attachments: { id: nil })

    scores = scores.limit(limit) if limit

    total = scores.count
    puts "Downloading MuseScore thumbnails for #{total} PDMX scores..."
    puts ""

    success_count = 0
    failed_count = 0
    skipped_count = 0

    scores.find_each.with_index do |score, index|
      print "  [#{index + 1}/#{total}] #{score.title[0..50]}... "

      begin
        # Read metadata JSON
        metadata_path = File.join(
          ENV.fetch("PDMX_DATA_PATH", File.expand_path("~/data/pdmx")),
          score.metadata_path.sub(/^\.\//, "")
        )

        unless File.exist?(metadata_path)
          print "✗ (no metadata file)\n"
          skipped_count += 1
          next
        end

        metadata = JSON.parse(File.read(metadata_path))
        thumbnails = metadata.dig("data", "score", "thumbnails")

        unless thumbnails
          print "✗ (no thumbnails in metadata)\n"
          skipped_count += 1
          next
        end

        # Download and attach thumbnail (medium size - for grid)
        medium_url = thumbnails["medium"]  # 300x420
        if medium_url
          download_and_attach(score, medium_url, :thumbnail_image)
        end

        # Download and attach preview (original/full resolution - for detail view)
        original_url = thumbnails["original"]  # ~827x1169 - crispy quality
        if original_url
          download_and_attach(score, original_url, :preview_image)
        end

        print "✓\n"
        success_count += 1

        # Rate limiting - be nice to MuseScore's CDN
        sleep(0.1) if (index + 1) % 10 == 0
      rescue => e
        print "✗ (#{e.message})\n"
        failed_count += 1
      end
    end

    puts ""
    puts "Done! Success: #{success_count}, Skipped: #{skipped_count}, Failed: #{failed_count}"
  end

  desc "Queue background jobs to download MuseScore thumbnails"
  task :enqueue_thumbnails, [:limit] => :environment do |_t, args|
    limit = args[:limit]&.to_i

    scores = Score.from_pdmx
                  .where.not(metadata_path: [nil, "", "N/A"])
                  .left_joins(:thumbnail_image_attachment)
                  .where(active_storage_attachments: { id: nil })

    scores = scores.limit(limit) if limit

    total = scores.count
    puts "Enqueueing #{total} MuseScore thumbnail download jobs..."

    scores.find_each do |score|
      DownloadMusescoreThumbnailsJob.perform_later(score.id)
    end

    puts "Done! Run job queue to process."
  end

  private

  def download_and_attach(score, url, attachment_name)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true if uri.scheme == "https"
    # Disable SSL verification due to CRL issues (same as CPDL importer)
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "ScorebaseBot/1.0"

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      raise "HTTP #{response.code}"
    end

    # Attach to Active Storage
    score.public_send(attachment_name).attach(
      io: StringIO.new(response.body),
      filename: "#{score.id}_#{attachment_name}.png",
      content_type: "image/png"
    )
  end
end
