# frozen_string_literal: true

namespace :rag do
  desc "Generate search_text for RAG. LIMIT=100, BACKEND=groq, MODEL=llama-4-scout, SCOPE=priority, FORCE=false"
  task generate: :environment do
    limit = ENV.fetch("LIMIT", "100").to_i
    backend = ENV.fetch("BACKEND", "groq").to_sym
    model = ENV.fetch("MODEL", "meta-llama/llama-4-scout-17b-16e-instruct")
    scope = ENV["SCOPE"]
    force = ENV["FORCE"] == "true"

    if scope == "priority"
      puts "Scope: priority (balanced: SATB + Guitar + Solo vocal + Bach/Mozart/Handel)"
      puts
    end

    GenerateSearchTextJob.perform_now(limit: limit, backend: backend, model: model, scope: scope, force: force)
    print_rag_stats
  end

  desc "Reset search_text generation. SCOPE=failed|templated|all"
  task reset: :environment do
    scope = ENV.fetch("SCOPE", "failed")

    count = case scope
    when "failed"
      Score.rag_failed.update_all(rag_status: "ready", search_text: nil, search_text_generated_at: nil)
    when "templated"
      Score.rag_templated.update_all(rag_status: "ready", search_text: nil, search_text_generated_at: nil)
    when "all"
      Score.where(rag_status: %w[templated failed]).update_all(rag_status: "ready", search_text: nil, search_text_generated_at: nil)
    else
      abort "Unknown scope: #{scope}. Use SCOPE=failed|templated|all"
    end

    puts "Reset #{count} scores to rag_status=ready"
  end

  desc "Mark ready_for_rag? scores as ready"
  task mark_ready: :environment do
    # Single SQL update matching ready_for_rag? logic:
    # (voicing_normalized + voicing) OR (instruments_normalized + instruments)
    # AND (composer_normalized + valid composer) OR (genre_normalized + genre)
    count = Score.rag_pending
      .where(
        "(voicing_status = 'normalized' AND voicing IS NOT NULL AND voicing != '') OR " \
        "(instruments_status = 'normalized' AND instruments IS NOT NULL AND instruments != '')"
      )
      .where(
        "(composer_status = 'normalized' AND composer IS NOT NULL AND composer != '' AND composer != 'NA') OR " \
        "(genre_status = 'normalized' AND genre IS NOT NULL AND genre != '')"
      )
      .update_all(rag_status: "ready")

    puts "Marked #{count} scores as ready for RAG"
    print_rag_stats
  end

  desc "Show normalization and RAG pipeline stats"
  task stats: :environment do
    total = Score.count

    puts "RAG Pipeline Status"
    puts "=" * 80

    # ─────────────────────────────────────────────────────────────────
    # NORMALIZATION STEPS (run these to grow the RAG-ready pool)
    # ─────────────────────────────────────────────────────────────────
    puts
    puts "NORMALIZATION (run to grow RAG pool)"
    puts "-" * 40

    # 1. Composer
    composer_eligible = Score.composer_pending.count
    puts "1. Composer:    #{format_step(:composer_status, composer_eligible)}"

    # 2. Period
    period_eligible = Score.period_pending
      .composer_normalized
      .where.not(composer: [nil, ""])
      .count
    puts "2. Period:      #{format_step(:period_status, period_eligible)}"

    # 3. Vocal Detection
    vocal_eligible = Score.has_vocal_pending
      .where(extraction_status: "extracted")
      .where.not(composer_status: "pending")
      .where.not(period_status: "pending")
      .count
    puts "3. Vocal:       #{format_step(:has_vocal_status, vocal_eligible)}"

    # 4. Voicing (vocal scores)
    voicing_eligible = Score.voicing_pending
      .has_vocal_normalized
      .where(has_vocal: true)
      .where.not(part_names: [nil, ""])
      .count
    puts "4. Voicing:     #{format_step(:voicing_status, voicing_eligible)}"

    # 5. Instruments (instrumental scores)
    instruments_eligible = Score.instruments_pending
      .has_vocal_normalized
      .where(has_vocal: false)
      .where.not(composer_status: "pending")
      .where.not(period_status: "pending")
      .where.not(title: [nil, ""])
      .count
    puts "5. Instruments: #{format_step(:instruments_status, instruments_eligible)}"

    # 6. Genre
    genre_eligible = Score.genre_pending
      .where.not(composer_status: "pending")
      .where.not(period_status: "pending")
      .where.not(has_vocal_status: "pending")
      .where.not(instruments_status: "pending")
      .where.not(title: [nil, ""])
      .count
    puts "6. Genre:       #{format_step(:genre_status, genre_eligible)}"

    # ─────────────────────────────────────────────────────────────────
    # RAG PIPELINE (scores that pass ready_for_rag?)
    # ─────────────────────────────────────────────────────────────────
    puts
    puts "RAG PIPELINE"
    puts "-" * 40

    # Use Ruby for accurate count matching ready_for_rag? exactly
    rag_ready_count = Score.rag_pending.count(&:ready_for_rag?)
    rag_statuses = Score.group(:rag_status).count

    ready = rag_statuses["ready"] || 0
    templated = rag_statuses["templated"] || 0
    indexed = rag_statuses["indexed"] || 0
    failed = rag_statuses["failed"] || 0

    puts "Eligible (pass ready_for_rag?):  #{rag_ready_count} ← run rag:mark_ready"
    puts "Ready (awaiting templating):     #{ready} ← run rag:generate"
    puts "Templated (awaiting indexing):   #{templated} ← run python indexer"
    puts "Indexed (in ChromaDB):           #{indexed}"
    puts "Failed:                          #{failed}" if failed > 0

    # ─────────────────────────────────────────────────────────────────
    # BLOCKERS (why scores can't reach RAG)
    # ─────────────────────────────────────────────────────────────────
    puts
    puts "BLOCKERS (why scores aren't RAG-ready)"
    puts "-" * 40

    missing_instrumentation = Score
      .where(voicing: [nil, ""])
      .where(instruments: [nil, ""])
      .count
    missing_identity = Score
      .where.not(voicing: [nil, ""])
      .or(Score.where.not(instruments: [nil, ""]))
      .where.not(composer_status: "normalized")
      .or(Score.where(composer: ["NA", nil, ""]))
      .where.not(genre_status: "normalized")
      .count

    puts "Missing voicing/instruments: #{missing_instrumentation}"
    puts "  → Run normalize:voicing (vocal) or normalize:instruments (instrumental)"

    # ─────────────────────────────────────────────────────────────────
    # SUMMARY
    # ─────────────────────────────────────────────────────────────────
    puts
    puts "=" * 80
    puts "NEXT STEPS:"
    if rag_ready_count > 0
      puts "  1. bin/rails rag:mark_ready           # Move #{rag_ready_count} → ready"
    end
    if ready > 0 || rag_ready_count > 0
      puts "  2. bin/rails rag:generate LIMIT=1000  # Generate search_text"
    end
    if templated > 0
      puts "  3. cd rag && python -m rag.src.pipeline.indexer -1  # Index to ChromaDB"
    end
    if rag_ready_count == 0 && ready == 0 && templated == 0
      puts "  Run normalization tasks to grow the RAG-ready pool"
    end
    puts
    puts "Total: #{total} | RAG-ready: #{rag_ready_count + ready + templated + indexed} | Indexed: #{indexed}"
  end

  def format_step(status_field, eligible_count)
    counts = Score.group(status_field).count
    normalized = counts["normalized"] || 0
    failed = counts["failed"] || 0
    pending = counts["pending"] || 0

    parts = ["#{normalized} done"]
    parts << "#{failed} failed" if failed > 0
    parts << "#{eligible_count} eligible" if eligible_count > 0
    parts.join(" | ")
  end

  def print_rag_stats
    puts
    puts "RAG Pipeline Status:"
    Score.group(:rag_status).count.sort.each { |k, v| puts "  #{k.ljust(15)} #{v}" }
  end
end
