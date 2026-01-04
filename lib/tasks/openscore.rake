namespace :openscore do
  desc "Import all scores from OpenScore Lieder corpus"
  task import: :environment do
    OpenscoreImporter.new.import!
  end

  desc "Import a sample of OpenScore scores. Use openscore:sample[100]"
  task :sample, [:limit] => :environment do |_t, args|
    limit = (args[:limit] || 10).to_i
    OpenscoreImporter.new(limit: limit).import!
  end

  namespace :quartets do
    desc "Import all scores from OpenScore String Quartets corpus"
    task import: :environment do
      OpenscoreQuartetsImporter.new.import!
    end

    desc "Import a sample of OpenScore String Quartets. Use openscore:quartets:sample[100]"
    task :sample, [:limit] => :environment do |_t, args|
      limit = (args[:limit] || 10).to_i
      OpenscoreQuartetsImporter.new(limit: limit).import!
    end
  end

  desc "Show OpenScore import statistics"
  task stats: :environment do
    total = Score.where(source: "openscore-lieder").count
    puts "OpenScore Lieder Scores: #{total}"
    puts ""

    if total > 0
      puts "By composer (top 10):"
      Score.where(source: "openscore-lieder")
        .group(:composer)
        .order("count_all DESC")
        .limit(10)
        .count
        .each { |composer, count| puts "  #{composer || 'Unknown'}: #{count}" }

      puts ""
      puts "With lyrics: #{Score.where(source: 'openscore-lieder', has_extracted_lyrics: true).count}"
      puts "With MusicXML: #{Score.where(source: 'openscore-lieder').where.not(mxl_path: [nil, '']).count}"

      puts ""
      puts "With key signature: #{Score.where(source: 'openscore-lieder').where.not(key_signature: [nil, '']).count}"
      puts "With time signature: #{Score.where(source: 'openscore-lieder').where.not(time_signature: [nil, '']).count}"

      puts ""
      puts "By period:"
      Score.where(source: "openscore-lieder")
        .group(:period)
        .order("count_all DESC")
        .count
        .each { |period, count| puts "  #{period || 'Unknown'}: #{count}" }
    end
  end

  desc "Clear all OpenScore scores from database"
  task clear: :environment do
    count = Score.where(source: "openscore-lieder").count
    print "This will delete #{count} OpenScore Lieder scores. Continue? (y/N) "
    confirm = $stdin.gets.chomp.downcase

    if confirm == "y"
      Score.where(source: "openscore-lieder").delete_all
      puts "Deleted #{count} OpenScore Lieder scores."
    else
      puts "Aborted."
    end
  end

  desc "Link local PDFs to OpenScore scores (sets pdf_path based on existing files)"
  task link_pdfs: :environment do
    base_path = Rails.application.config.x.openscore_pdfs_path
    puts "=== Linking OpenScore PDFs ==="
    puts "Looking in: #{base_path}"
    puts ""

    unless base_path.exist?
      puts "ERROR: Path does not exist: #{base_path}"
      puts "Upload PDFs to #{base_path}/{lieder,quartets}/ first"
      exit 1
    end

    [
      { source: "openscore-lieder", folder: "lieder" },
      { source: "openscore-quartets", folder: "quartets" }
    ].each do |config|
      source = config[:source]
      folder = config[:folder]
      folder_path = base_path.join(folder)

      unless folder_path.exist?
        puts "#{source}: Folder #{folder_path} not found, skipping"
        next
      end

      # Find scores without pdf_path set
      scores = Score.where(source: source)
                    .where("pdf_path IS NULL OR pdf_path = ''")
                    .where.not(external_id: [nil, ""])

      total = scores.count
      puts "#{source}: #{total} scores need pdf_path"

      linked = 0
      missing = 0

      scores.find_each do |score|
        pdf_file = folder_path.join("#{score.external_id}.pdf")

        if pdf_file.exist?
          score.update_columns(pdf_path: "#{folder}/#{score.external_id}.pdf")
          linked += 1
        else
          missing += 1
        end
      end

      puts "  Linked: #{linked}, Missing PDF: #{missing}"
    end

    puts ""
    puts "=== Done ==="
    puts "Run 'bin/rails openscore:generate_visuals' to generate thumbnails and galleries"
  end

  desc "Fix missing mxl_path by searching for actual files on disk"
  task fix_mxl_paths: :environment do
    puts "=== Fixing missing mxl_path for OpenScore scores ==="

    [
      { source: "openscore-lieder", prefix: "lc", root: Rails.application.config.x.openscore_path },
      { source: "openscore-quartets", prefix: "sq", root: Rails.application.config.x.openscore_quartets_path }
    ].each do |config|
      root = config[:root]
      next unless root.exist?

      scores = Score.where(source: config[:source])
                    .where(mxl_path: [nil, ""])
                    .where.not(external_id: [nil, ""])

      total = scores.count
      puts "#{config[:source]}: #{total} scores need mxl_path fix"
      next if total.zero?

      # Build lookup hash: external_id => relative_path (fast, single scan)
      puts "  Scanning #{root} for MXL files..."
      mxl_lookup = {}
      Dir.glob(root.join("**", "#{config[:prefix]}*.mxl").to_s).each do |path|
        # Extract external_id from filename: lc6623221.mxl -> 6623221
        filename = File.basename(path, ".mxl")
        external_id = filename.sub(/^#{config[:prefix]}/, "")
        relative = path.sub(root.to_s + "/", "./")
        mxl_lookup[external_id] = relative
      end
      puts "  Found #{mxl_lookup.size} MXL files on disk"

      fixed = 0
      not_found = 0

      scores.find_each do |score|
        if (relative_path = mxl_lookup[score.external_id])
          score.update_columns(mxl_path: relative_path)
          fixed += 1
        else
          not_found += 1
        end
      end

      puts "  Fixed: #{fixed}, Not found: #{not_found}"
    end

    puts "=== Done ==="
  end

  desc "Generate thumbnails and galleries for OpenScore scores with PDFs"
  task generate_visuals: :environment do
    puts "=== Generating thumbnails for OpenScore scores ==="

    %w[openscore-lieder openscore-quartets].each do |source|
      # Scores with pdf_path but no thumbnail
      scores = Score.where(source: source)
                    .where.not(pdf_path: [nil, ""])
                    .left_joins(:thumbnail_image_attachment)
                    .where(active_storage_attachments: { id: nil })

      count = scores.count
      puts "#{source}: #{count} scores need thumbnails"

      scores.find_each do |score|
        GenerateThumbnailJob.perform_later(score.id)
      end
    end

    puts ""
    puts "=== Generating galleries for OpenScore scores ==="

    %w[openscore-lieder openscore-quartets].each do |source|
      # Scores with pdf_path but no gallery pages
      scores = Score.where(source: source)
                    .where.not(pdf_path: [nil, ""])
                    .left_joins(:score_pages)
                    .where(score_pages: { id: nil })

      count = scores.count
      puts "#{source}: #{count} scores need galleries"

      scores.find_each do |score|
        GenerateGalleryJob.perform_later(score.id)
      end
    end

    puts ""
    puts "=== Jobs enqueued ==="
    puts "Run 'bin/jobs' to process the queue"
  end
end
