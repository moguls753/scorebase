# frozen_string_literal: true

namespace :rag do
  desc "Generate search_text for RAG. LIMIT=100, BACKEND=groq|lmstudio, FORCE=false"
  task generate: :environment do
    limit = ENV.fetch("LIMIT", 100).to_i
    backend = ENV.fetch("BACKEND", "groq").to_sym
    force = ENV.fetch("FORCE", "false") == "true"

    GenerateSearchTextJob.perform_now(limit: limit, backend: backend, force: force)
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
    count = 0
    Score.rag_pending.find_each do |score|
      if score.ready_for_rag?
        score.update!(rag_status: :ready)
        count += 1
      end
    end
    puts "Marked #{count} scores as ready for RAG"
    print_rag_stats
  end

  desc "Show normalization and RAG pipeline stats"
  task stats: :environment do
    total = Score.count

    puts "RAG Pipeline Status"
    puts "=" * 80

    # 1. Composer (no prerequisites)
    puts
    puts "1. Composer Normalization"
    puts "   Scope: all scores"
    print_step_stats(:composer_status, total)

    # 2. Period (requires composer_normalized)
    puts
    puts "2. Period Normalization"
    period_scope = Score.composer_normalized.count
    puts "   Scope: composer_normalized (#{period_scope})"
    print_step_stats(:period_status, period_scope)

    # 3. Vocal Detection (requires composer processed)
    puts
    puts "3. Vocal Detection"
    vocal_scope = Score.where.not(composer_status: "pending").count
    puts "   Scope: composer processed (#{vocal_scope})"
    print_step_stats(:has_vocal_status, vocal_scope)

    # 4. Voicing (requires has_vocal=true, has_vocal_status=normalized)
    puts
    puts "4. Voicing Normalization (vocal scores only)"
    voicing_scope = Score.has_vocal_normalized.where(has_vocal: true).count
    puts "   Scope: has_vocal=true & normalized (#{voicing_scope})"
    print_step_stats(:voicing_status, voicing_scope)

    # 5. Instruments (requires has_vocal=false OR voicing done for vocal)
    puts
    puts "5. Instruments Normalization"
    instr_scope = Score.has_vocal_normalized.where(has_vocal: false).count
    puts "   Scope: has_vocal=false & normalized (#{instr_scope})"
    print_step_stats(:instruments_status, instr_scope)

    # 6. Genre (requires all prior steps processed)
    puts
    puts "6. Genre Normalization"
    genre_scope = Score.genre_pending
      .where.not(composer_status: "pending")
      .where.not(period_status: "pending")
      .where.not(has_vocal_status: "pending")
      .where.not(instruments_status: "pending")
      .where.not(title: [nil, ""])
      .count
    genre_done = Score.genre_normalized.count + Score.genre_not_applicable.count
    genre_failed = Score.genre_failed.count
    puts "   Eligible to process: #{genre_scope}"
    puts "   Done:    #{genre_done}"
    puts "   Failed:  #{genre_failed}"

    # 7. RAG Ready
    puts
    puts "7. RAG Pipeline"
    with_voicing = Score.where.not(voicing: [nil, ""]).count
    with_instruments = Score.where.not(instruments: [nil, ""]).count
    with_instr_total = Score.where.not(voicing: [nil, ""]).or(Score.where.not(instruments: [nil, ""])).count

    # RAG ready = instrumentation + (composer OR genre)
    with_instr_and_composer = Score
      .where.not(voicing: [nil, ""])
      .or(Score.where.not(instruments: [nil, ""]))
      .where(composer_status: "normalized")
      .where.not(composer: ["NA", nil, ""])
      .count
    with_instr_and_genre = Score
      .where.not(voicing: [nil, ""])
      .or(Score.where.not(instruments: [nil, ""]))
      .where(genre_status: "normalized")
      .count
    # Rough estimate (some overlap)
    rag_ready_estimate = with_instr_and_composer

    puts "   With voicing:         #{with_voicing}"
    puts "   With instruments:     #{with_instruments}"
    puts "   With either:          #{with_instr_total}"
    puts "   + known composer:     #{with_instr_and_composer} (RAG ready now)"
    puts "   + genre normalized:   #{with_instr_and_genre}"
    puts
    Score.group(:rag_status).count.sort.each { |k, v| puts "   #{k.ljust(15)} #{v}" }

    puts
    puts "=" * 80
    puts "Summary:"
    puts "  Total scores:      #{total}"
    puts "  RAG ready (est):   #{rag_ready_estimate}"
    puts "  Blocked by instr:  #{total - with_instr_total}"
  end

  def print_step_stats(status_field, scope_count)
    counts = Score.group(status_field).count
    normalized = counts["normalized"] || 0
    not_applicable = counts["not_applicable"] || 0
    pending = counts["pending"] || 0
    failed = counts["failed"] || 0
    done = normalized + not_applicable

    # Eligible = scope minus what's already done/failed (can't exceed pending)
    eligible = [scope_count - done - failed, 0].max.clamp(0, pending)

    puts "   Normalized:  #{normalized}"
    puts "   N/A:         #{not_applicable}" if not_applicable > 0
    puts "   Failed:      #{failed}" if failed > 0
    puts "   Pending:     #{pending} (#{eligible} eligible)"
  end

  def print_rag_stats
    puts
    puts "RAG Pipeline Status:"
    Score.group(:rag_status).count.sort.each { |k, v| puts "  #{k.ljust(15)} #{v}" }
  end
end
