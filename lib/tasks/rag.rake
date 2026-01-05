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
    puts "RAG Pipeline Status"
    puts "=" * 80
    puts
    puts "1. Composer Normalization (composer_status):"
    Score.group(:composer_status).count.sort.each { |k, v| puts "  #{k.ljust(15)} #{v}" }
    puts
    puts "2. Period Normalization (period_status):"
    Score.group(:period_status).count.sort.each { |k, v| puts "  #{k.ljust(15)} #{v}" }
    puts
    puts "3. Vocal Detection (has_vocal_status):"
    Score.group(:has_vocal_status).count.sort.each { |k, v| puts "  #{k.ljust(15)} #{v}" }
    puts
    puts "4. Voicing Normalization (voicing_status) - vocal scores:"
    Score.group(:voicing_status).count.sort.each { |k, v| puts "  #{k.ljust(15)} #{v}" }
    puts
    puts "5. Instruments Normalization (instruments_status) - instrumental scores:"
    Score.group(:instruments_status).count.sort.each { |k, v| puts "  #{k.ljust(15)} #{v}" }
    puts
    puts "6. Genre Normalization (genre_status):"
    Score.group(:genre_status).count.sort.each { |k, v| puts "  #{k.ljust(15)} #{v}" }
    puts
    puts "7. Search Text Generation (rag_status):"
    Score.group(:rag_status).count.sort.each { |k, v| puts "  #{k.ljust(15)} #{v}" }
    puts
    puts "=" * 80
    puts "Summary:"
    puts "  Ready for RAG: #{Score.where(rag_status: 'ready').count}"
    puts "  Total scores:  #{Score.count}"
  end

  def print_rag_stats
    puts
    puts "RAG Pipeline Status:"
    Score.group(:rag_status).count.sort.each { |k, v| puts "  #{k.ljust(15)} #{v}" }
  end
end
