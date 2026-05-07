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
      puts "Set PDMX_DATA_PATH env var or download from: https://zenodo.org/records/15571083"
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

  desc "Backfill PDMX scores where title='NA'/'Untitled' using csv.title (then subtitle, song_name)"
  task backfill_titles: :environment do
    require "csv"

    dry_run = ENV["DRY_RUN"] == "true"
    bad_titles = ["NA", "N/A", "Untitled", ""]

    candidates = Score.where(source: "pdmx", title: bad_titles)
    total = candidates.count
    puts "PDMX rows with bad titles: #{total}"
    next if total.zero?

    csv_path = Rails.application.config.x.pdmx_path.join("PDMX.csv")
    unless csv_path.exist?
      puts "PDMX.csv not found at #{csv_path}"
      exit 1
    end

    needed_paths = candidates.pluck(:data_path).compact.to_set
    puts "Loading CSV for #{needed_paths.size} target rows..."

    csv_lookup = {}
    CSV.foreach(csv_path, headers: true) do |row|
      next unless needed_paths.include?(row["path"])
      csv_lookup[row["path"]] = row.to_h.slice("title", "subtitle", "song_name")
    end
    puts "Matched #{csv_lookup.size} CSV rows"

    blank_or_na = ->(v) { v.blank? || %w[NA N/A].include?(v.to_s.strip) }
    clean = ->(v) { v.to_s.strip.tr("_", " ").squeeze(" ") }

    fixed_ids = []
    no_csv = 0
    no_title = 0

    candidates.find_each do |score|
      row = csv_lookup[score.data_path]
      if row.nil?
        no_csv += 1
        next
      end

      new_title = nil
      ["title", "subtitle", "song_name"].each do |field|
        val = row[field]
        next if blank_or_na.call(val)
        candidate = clean.call(val)
        next if candidate.blank?
        new_title = candidate
        break
      end

      if new_title.nil?
        no_title += 1
        next
      end

      if dry_run
        puts "[#{score.id}] #{score.title.inspect} -> #{new_title.inspect}"
      else
        score.update!(title: new_title)
      end
      fixed_ids << score.id
    end

    puts ""
    puts "Fixed: #{fixed_ids.size}#{' (DRY RUN, no changes saved)' if dry_run}"
    puts "Skipped (no CSV row matched data_path): #{no_csv}"
    puts "Skipped (no usable title in CSV): #{no_title}"

    if !dry_run && fixed_ids.any?
      stale = Score.where(id: fixed_ids, rag_status: %w[templated indexed failed])
      stale_ids = stale.pluck(:id)
      stale.update_all(rag_status: "pending", search_text: nil, search_text_generated_at: nil)

      queue_path = Rails.root.join("storage", "rag_reindex_queue.txt")
      File.write(queue_path, stale_ids.join("\n"))

      puts ""
      puts "RAG reset: #{stale_ids.size} rows -> rag_status=pending, search_text=nil"
      puts "Wrote IDs to: #{queue_path}"
      puts ""
      puts "Next steps to refresh embeddings:"
      puts "  1. Purge those IDs from ChromaDB (one-off):"
      puts "       cd rag && python -c \""
      puts "     from haystack_integrations.document_stores.chroma import ChromaDocumentStore"
      puts "     from src import config"
      puts "     ids = [int(x) for x in open('#{queue_path}').read().split() if x.strip()]"
      puts "     ds = ChromaDocumentStore(persist_path=str(config.CHROMA_PATH))"
      puts "     ds._collection.delete(ids=[f'score_{i}' for i in ids])"
      puts "     print(f'Deleted {len(ids)} docs')"
      puts "     \""
      puts "  2. Re-template + re-index through normal pipeline:"
      puts "       bin/rails rag:mark_ready"
      puts "       bin/rails rag:generate LIMIT=#{stale_ids.size}"
      puts "       cd rag && python -m src.pipeline.indexer #{stale_ids.size}"
    end
  end

  # NOTE: Thumbnail generation tasks moved to images.rake
  # Use: bin/rails images:thumbnails[pdmx] or images:enqueue_thumbnails[pdmx]
end
