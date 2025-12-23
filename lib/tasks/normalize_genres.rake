# frozen_string_literal: true

namespace :normalize do
  desc "Infer genres using LLM. LIMIT=100, BACKEND=groq|gemini|lmstudio. Requires: composer processed, instruments processed"
  task genres: :environment do
    limit = ENV.fetch("LIMIT", 100).to_i
    backend = ENV.fetch("BACKEND", "groq").to_sym

    NormalizeGenresJob.perform_now(limit: limit, backend: backend)
    print_genre_stats
  end

  desc "Reset genre normalization. SCOPE=all|failed"
  task reset_genres: :environment do
    scope = ENV.fetch("SCOPE", "failed")

    count = case scope
    when "all"
      Score.where.not(genre_status: "pending").update_all(genre_status: "pending", genre: nil)
    when "failed"
      Score.genre_failed.update_all(genre_status: "pending")
    else
      abort "Unknown scope: #{scope}. Use SCOPE=all or SCOPE=failed"
    end

    puts "Reset #{count} scores to genre_status=pending"
  end

  def print_genre_stats
    puts
    puts "Database totals:"
    puts "  Normalized:     #{Score.genre_normalized.count}"
    puts "  Not applicable: #{Score.genre_not_applicable.count}"
    puts "  Failed:         #{Score.genre_failed.count}"
    puts "  Pending:        #{Score.genre_pending.count}"
  end
end
