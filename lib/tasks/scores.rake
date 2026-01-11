# frozen_string_literal: true

namespace :scores do
  desc "Batch extract musical features using music21. LIMIT=100, FORCE=false, DEBUG=false, WORKERS=0"
  task batch_extract: :environment do
    require "tempfile"
    require "open3"

    limit = ENV.fetch("LIMIT", "100").to_i
    force = ENV.fetch("FORCE", "false") == "true"
    debug = ENV.fetch("DEBUG", "false") == "true"
    workers = ENV.fetch("WORKERS", "0").to_i  # 0 = auto-detect CPU cores

    # Find scores that need extraction (local sources only - PDMX, OpenScore)
    local_sources = %w[pdmx openscore-lieder openscore-quartets]
    scope = force ? Score.where(source: local_sources) : Score.extraction_pending.where(source: local_sources)
    scope = scope.where.not(mxl_path: [nil, "", "N/A"])
    scope = scope.limit(limit)

    scores = scope.to_a
    puts "Found #{scores.size} scores to extract (sources: #{scores.map(&:source).tally})"

    next if scores.empty?

    # Build paths list with score IDs (use model's mxl_url for correct path resolution)
    missing_files = []
    paths_with_ids = scores.filter_map do |score|
      next unless score.has_mxl?

      full_path = score.mxl_url
      unless full_path && File.exist?(full_path)
        missing_files << { id: score.id, source: score.source, mxl_path: score.mxl_path, resolved: full_path }
        next
      end

      puts "  [#{score.source}] #{score.id}: #{full_path}" if debug
      [score.id, full_path]
    end

    puts "#{paths_with_ids.size} scores have valid MXL files"

    if missing_files.any?
      puts "\nSkipped #{missing_files.size} scores (files not found):"
      missing_files.first(5).each do |m|
        puts "  [#{m[:source]}] #{m[:id]}: #{m[:mxl_path]}"
        puts "    resolved to: #{m[:resolved] || '(nil)'}"
      end
      puts "  ... and #{missing_files.size - 5} more" if missing_files.size > 5
    end

    next if paths_with_ids.empty?

    # Write paths to temp file
    paths_file = Tempfile.new(["extract_paths", ".txt"])
    paths_file.write(paths_with_ids.map(&:last).join("\n"))
    paths_file.close

    id_by_path = paths_with_ids.to_h { |id, path| [path, id] }

    # Run Python batch extraction
    script = Rails.root.join("rag/extract.py").to_s
    python = ENV.fetch("PYTHON_CMD", "python3")
    output_file = Tempfile.new(["extract_results", ".jsonl"])
    output_file.close

    puts "\nRunning Python extraction on #{paths_with_ids.size} files (workers: #{workers == 0 ? 'auto' : workers})..."
    status = nil
    Open3.popen3(python, script, "--batch", paths_file.path, "--output", output_file.path, "--workers", workers.to_s) do |_stdin, _stdout, stderr, wait_thr|
      # Stream stderr (progress) to console in real-time
      stderr.each_line { |line| puts "  #{line}" }
      status = wait_thr.value
    end

    unless status&.success?
      puts "Extraction failed (exit code: #{status&.exitstatus})"
      next
    end

    # Import results using Music21Extractor for consistency
    puts "\nImporting results to database..."
    imported = 0
    failed = 0
    parse_errors = 0

    File.foreach(output_file.path) do |line|
      result = begin
        JSON.parse(line)
      rescue JSON::ParserError => e
        parse_errors += 1
        puts "\n  JSON parse error: #{e.message}" if debug
        next
      end

      file_path = result.delete("file_path")
      score_id = id_by_path[file_path]

      unless score_id
        puts "\n  Unknown file_path in result: #{file_path}" if debug
        next
      end

      score = Score.find_by(id: score_id)
      unless score
        puts "\n  Score not found: #{score_id}" if debug
        next
      end

      # Delegate to Music21Extractor for consistent result application
      extractor = Music21Extractor.new(score)
      extractor.send(:apply_result, result)

      if score.reload.extraction_extracted?
        imported += 1
        puts "  #{imported}. #{score.title&.truncate(50)} (#{score.source})" if debug
      else
        failed += 1
        puts "\n  Failed: #{score.id} - #{score.extraction_error}" if debug
      end

      print "\r  Progress: #{imported} imported, #{failed} failed" unless debug
    rescue => e
      puts "\n  Error on score #{score_id}: #{e.message}"
      failed += 1
    end

    puts "\n\nDone: #{imported} imported, #{failed} failed"
    puts "  (#{parse_errors} JSON parse errors)" if parse_errors > 0
  ensure
    paths_file&.unlink
    output_file&.unlink
  end

  desc "Recompute difficulty using instrument-aware Ruby calculator. LIMIT=all or number"
  task recompute_difficulty: :environment do
    limit = ENV.fetch("LIMIT", "all")
    scope = Score.extraction_extracted

    scope = scope.limit(limit.to_i) unless limit == "all"

    total = scope.count
    updated = 0
    errors = 0

    puts "Recomputing difficulty for #{total} scores..."

    scope.find_each.with_index do |score, i|
      old_difficulty = score.computed_difficulty
      new_difficulty = DifficultyCalculator.new(score).compute

      if old_difficulty != new_difficulty
        score.update_column(:computed_difficulty, new_difficulty)
        updated += 1
      end

      print "\r  Progress: #{i + 1}/#{total} (#{updated} updated)"
    rescue => e
      errors += 1
      puts "\n  Error on score #{score.id}: #{e.message}"
    end

    puts
    puts "Done: #{updated} updated, #{errors} errors"
    print_difficulty_distribution
  end

  desc "Compute derived metrics and store in columns. LIMIT=all or number"
  task compute_metrics: :environment do
    limit = ENV.fetch("LIMIT", "all")
    scope = Score.extraction_extracted

    scope = scope.limit(limit.to_i) unless limit == "all"

    total = scope.count
    updated = 0

    puts "Computing derived metrics for #{total} scores..."

    scope.find_each.with_index do |score, i|
      metrics = ScoreMetricsCalculator.new(score)

      # Update derived columns (these are now computed from raw data)
      score.update_columns(
        note_density: metrics.note_density,
        chromatic_complexity: metrics.chromatic_ratio,
        syncopation_level: metrics.syncopation_level,
        rhythmic_variety: metrics.rhythmic_variety,
        harmonic_rhythm: metrics.harmonic_rhythm,
        stepwise_motion_ratio: metrics.stepwise_ratio,
        voice_independence: metrics.voice_independence,
        vertical_density: metrics.vertical_density,
        leaps_per_measure: score.measure_count&.positive? ? score.leap_count.to_f / score.measure_count : nil
      )

      updated += 1
      print "\r  Progress: #{i + 1}/#{total}"
    rescue => e
      puts "\n  Error on score #{score.id}: #{e.message}"
    end

    puts
    puts "Done: #{updated} scores updated"
  end

  desc "Generate labels for RAG search text"
  task generate_labels: :environment do
    limit = ENV.fetch("LIMIT", "100").to_i
    scope = Score.extraction_extracted.limit(limit)

    puts "Generating labels for #{scope.count} scores..."

    scope.find_each.with_index do |score, i|
      labeler = ScoreLabeler.new(score)
      labels = labeler.all

      # Store texture_type (derived label)
      if labels[:texture_type].present?
        score.update_column(:texture_type, labels[:texture_type])
      end

      print "\r  Progress: #{i + 1}/#{limit}"
    end

    puts
    puts "Done"
  end

  desc "Show difficulty distribution"
  task difficulty_stats: :environment do
    print_difficulty_distribution
  end

  desc "Extract chord_span for solo keyboard/harp scores missing it. LIMIT=1000"
  task extract_missing_chord_span: :environment do
    require "tempfile"
    require "open3"

    limit = ENV.fetch("LIMIT", "1000").to_i

    # Find solo keyboard/harp scores missing chord_span
    scope = Score.where(max_chord_span: nil)
                 .where(has_vocal: false)
                 .where.not(instruments: [nil, ""])
                 .where.not("instruments LIKE ?", "%,%")
                 .where.not(mxl_path: [nil, "", "N/A"])
                 .limit(limit)

    # Filter for applicable instruments in Ruby (SQLite lacks regex)
    scores = scope.to_a.select { |s| s.chord_span_applicable? }

    puts "Found #{scores.size} scores needing chord_span extraction"
    next if scores.empty?

    # Build paths list
    paths_with_ids = scores.filter_map do |score|
      full_path = score.mxl_url
      next unless full_path && File.exist?(full_path)
      [score.id, full_path]
    end

    puts "#{paths_with_ids.size} have valid MXL files"
    next if paths_with_ids.empty?

    # Write paths to temp file
    paths_file = Tempfile.new(["chord_span_paths", ".txt"])
    paths_file.write(paths_with_ids.map(&:last).join("\n"))
    paths_file.close

    id_by_path = paths_with_ids.to_h { |id, path| [path, id] }

    # Run Python extraction
    script = Rails.root.join("rag/extract_chord_span.py").to_s
    python = ENV.fetch("PYTHON_CMD", "python3")
    output_file = Tempfile.new(["chord_span_results", ".jsonl"])
    output_file.close

    puts "\nExtracting chord_span..."
    Open3.popen3(python, script, "--batch", paths_file.path, "--output", output_file.path) do |_stdin, _stdout, stderr, wait_thr|
      stderr.each_line { |line| print line }
      wait_thr.value
    end

    # Import results
    puts "Importing results..."
    updated = 0
    File.foreach(output_file.path) do |line|
      result = JSON.parse(line) rescue next
      score_id = id_by_path[result["file_path"]]
      next unless score_id && result["max_chord_span"]

      Score.where(id: score_id).update_all(max_chord_span: result["max_chord_span"])
      updated += 1
    end

    puts "Done. Updated #{updated} scores with chord_span."
  ensure
    paths_file&.unlink
    output_file&.unlink
  end

  desc "Re-extract keyboard/harp scores missing chord_span. LIMIT=all, WORKERS=0"
  task reextract_keyboard: :environment do
    require "tempfile"
    require "open3"

    limit = ENV.fetch("LIMIT", "all")
    workers = ENV.fetch("WORKERS", "0").to_i

    # Find keyboard/harp scores MISSING chord_span (Python skipped them with old instrument guessing)
    local_sources = %w[pdmx openscore-lieder openscore-quartets]
    scope = Score.where(source: local_sources)
                 .where(max_chord_span: nil)  # Missing chord_span
                 .where(has_vocal: false)
                 .where.not(instruments: [nil, ""])
                 .where.not("instruments LIKE ?", "%,%")
                 .where.not(mxl_path: [nil, "", "N/A"])

    scope = scope.limit(limit.to_i) unless limit == "all"
    scores = scope.to_a.select { |s| s.chord_span_applicable? }

    puts "Found #{scores.size} keyboard/harp scores to re-extract"
    next if scores.empty?

    # Build paths list
    paths_with_ids = scores.filter_map do |score|
      full_path = score.mxl_url
      next unless full_path && File.exist?(full_path)
      [score.id, full_path]
    end

    puts "#{paths_with_ids.size} have valid MXL files"
    next if paths_with_ids.empty?

    # Write paths to temp file
    paths_file = Tempfile.new(["keyboard_paths", ".txt"])
    paths_file.write(paths_with_ids.map(&:last).join("\n"))
    paths_file.close

    id_by_path = paths_with_ids.to_h { |id, path| [path, id] }

    # Run Python extraction
    script = Rails.root.join("rag/extract.py").to_s
    python = ENV.fetch("PYTHON_CMD", "python3")
    output_file = Tempfile.new(["keyboard_results", ".jsonl"])
    output_file.close

    puts "\nExtracting #{paths_with_ids.size} files (workers: #{workers == 0 ? 'auto' : workers})..."
    status = nil
    Open3.popen3(python, script, "--batch", paths_file.path, "--output", output_file.path, "--workers", workers.to_s) do |_stdin, _stdout, stderr, wait_thr|
      stderr.each_line { |line| puts "  #{line}" }
      status = wait_thr.value
    end

    unless status&.success?
      puts "Extraction failed (exit code: #{status&.exitstatus})"
      next
    end

    # Import results
    puts "\nImporting results..."
    imported = 0
    failed = 0

    File.foreach(output_file.path) do |line|
      result = JSON.parse(line) rescue next
      file_path = result.delete("file_path")
      score_id = id_by_path[file_path]
      next unless score_id

      score = Score.find_by(id: score_id)
      next unless score

      Music21Extractor.new(score).send(:apply_result, result)
      if score.reload.extraction_extracted?
        imported += 1
      else
        failed += 1
      end
      print "\r  Imported: #{imported}, failed: #{failed}"
    rescue => e
      puts "\n  Error on score #{score_id}: #{e.message}"
      failed += 1
    end

    puts "\nDone. Re-extracted #{imported} scores (#{failed} failed)."
  ensure
    paths_file&.unlink
    output_file&.unlink
  end

  desc "Backfill extraction context (nil chord_span for non-applicable instruments)"
  task backfill_extraction_context: :environment do
    # Find scores with chord_span (skip pending - callback will handle when normalized)
    scope = Score.where.not(max_chord_span: nil)
                 .where.not(instruments_status: :pending)

    total = scope.count
    puts "Checking #{total} scores with chord_span..."

    cleaned = 0
    scope.find_each.with_index do |score, i|
      unless score.chord_span_applicable?
        score.update_columns(max_chord_span: nil)
        cleaned += 1
      end
      print "\r  Progress: #{i + 1}/#{total} (cleaned: #{cleaned})" if (i + 1) % 100 == 0
    end

    puts "\nDone. Cleaned #{cleaned} scores."
  end

  def print_difficulty_distribution
    puts
    puts "Difficulty distribution:"
    (1..5).each do |level|
      count = Score.where(computed_difficulty: level).count
      label = DifficultyCalculator::DIFFICULTY_LABELS[level]
      bar = "#" * (count / 100)
      puts "  #{level} (#{label.ljust(12)}): #{count.to_s.rjust(6)} #{bar}"
    end
    puts "  nil:             #{Score.where(computed_difficulty: nil).count}"
  end
end
