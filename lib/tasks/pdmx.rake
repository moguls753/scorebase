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
    pdmx_path = Rails.application.config.x.pdmx_path
    unless pdmx_path.exist? && pdmx_path.join("PDMX.csv").exist?
      puts "PDMX dataset not found at: #{pdmx_path}"
      puts "Set PDMX_PATH environment variable or download from: https://zenodo.org/records/15571083"
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

  # NOTE: Thumbnail generation tasks moved to images.rake
  # Use: bin/rails images:thumbnails[pdmx] or images:enqueue_thumbnails[pdmx]
end
