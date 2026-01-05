# frozen_string_literal: true

namespace :normalize do
  desc "Validate has_vocal using LLM. LIMIT=100, BACKEND=openai|groq|gemini|lmstudio. Requires: extraction completed"
  task has_vocal: :environment do
    limit = ENV.fetch("LIMIT", 100).to_i
    backend = ENV.fetch("BACKEND", "openai").to_sym

    NormalizeHasVocalJob.perform_now(limit: limit, backend: backend)
    print_has_vocal_stats
  end

  desc "Reset has_vocal normalization. SCOPE=all|failed"
  task reset_has_vocal: :environment do
    scope = ENV.fetch("SCOPE", "failed")

    count = case scope
    when "all"
      Score.where.not(has_vocal_status: "pending").update_all(has_vocal_status: "pending")
    when "failed"
      Score.has_vocal_failed.update_all(has_vocal_status: "pending")
    else
      abort "Unknown scope: #{scope}. Use SCOPE=all or SCOPE=failed"
    end

    puts "Reset #{count} scores to has_vocal_status=pending"
  end

  def print_has_vocal_stats
    puts
    puts "Database totals:"
    puts "  Normalized: #{Score.has_vocal_normalized.count}"
    puts "  Failed:     #{Score.has_vocal_failed.count}"
    puts "  Pending:    #{Score.has_vocal_pending.count}"
  end
end
