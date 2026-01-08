# frozen_string_literal: true

namespace :scores do
  desc "Batch extract musical features using music21. LIMIT=100, FORCE=false, DEBUG=false"
  task batch_extract: :environment do
    require "tempfile"
    require "open3"

    limit = ENV.fetch("LIMIT", "100").to_i
    force = ENV.fetch("FORCE", "false") == "true"
    debug = ENV.fetch("DEBUG", "false") == "true"

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

    puts "\nRunning Python extraction on #{paths_with_ids.size} files..."
    _stdout, stderr, status = Open3.capture3(
      python, script, "--batch", paths_file.path, "--output", output_file.path
    )

    unless status.success?
      puts "Extraction failed: #{stderr}"
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
