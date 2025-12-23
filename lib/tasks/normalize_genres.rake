# frozen_string_literal: true

namespace :normalize do
  desc "Infer genres using LLM. LIMIT=100, BACKEND=groq|gemini|lmstudio"
  task genres: :environment do
    limit = ENV.fetch("LIMIT", 100).to_i
    backend = ENV.fetch("BACKEND", "groq").to_sym

    client = LlmClient.new(backend: backend)
    inferrer = GenreInferrer.new(client: client)

    scores = Score.genre_pending
                  .safe_for_ai
                  .where.not(title: [nil, ""])
                  .limit(limit)

    puts "Provider: #{backend}"
    puts "Pending: #{Score.genre_pending.count}"
    puts "Processing: #{scores.count}"
    puts

    stats = { normalized: 0, not_applicable: 0, failed: 0 }

    scores.each.with_index do |score, i|
      result = inferrer.infer(score)

      if result.found?
        score.update!(genre: result.genre, genre_status: :normalized)
        stats[:normalized] += 1
        puts "#{i + 1}. #{score.title[0..40]} -> #{result.genre} (#{result.confidence})"
      elsif result.success?
        # LLM returned null - genre not determinable but call succeeded
        score.update!(genre_status: :not_applicable)
        stats[:not_applicable] += 1
        puts "#{i + 1}. #{score.title[0..40]} -> N/A"
      else
        score.update!(genre_status: :failed)
        stats[:failed] += 1
        puts "#{i + 1}. #{score.title[0..40]} -> FAILED: #{result.error}"
      end

      sleep 0.1 if backend != :lmstudio
    end

    puts
    puts "=" * 50
    puts "This run:"
    puts "  Normalized:     #{stats[:normalized]}"
    puts "  Not applicable: #{stats[:not_applicable]}"
    puts "  Failed:         #{stats[:failed]}"
    puts
    puts "Database totals:"
    puts "  Normalized:     #{Score.genre_normalized.count}"
    puts "  Not applicable: #{Score.genre_not_applicable.count}"
    puts "  Failed:         #{Score.genre_failed.count}"
    puts "  Pending:        #{Score.genre_pending.count}"
  end

  desc "Reset genre normalization. SCOPE=all|failed (default: failed)"
  task reset_genres: :environment do
    scope = ENV.fetch("SCOPE", "failed")

    count = case scope
    when "all"
      Score.where.not(genre_status: "pending").update_all(genre_status: "pending")
    when "failed"
      Score.genre_failed.update_all(genre_status: "pending")
    else
      abort "Unknown scope: #{scope}. Use SCOPE=all or SCOPE=failed"
    end

    puts "Reset #{count} scores to genre_status=pending"
  end
end
