# frozen_string_literal: true

namespace :normalize do
  desc "Infer instruments using LLM. LIMIT=100, BACKEND=groq|gemini|lmstudio. Requires: composer processed"
  task instruments: :environment do
    limit = ENV.fetch("LIMIT", 100).to_i
    backend = ENV.fetch("BACKEND", "groq").to_sym

    NormalizeInstrumentsJob.perform_now(limit: limit, backend: backend)
    print_instrument_stats
  end

  desc "Reset instrument normalization. SCOPE=all|failed"
  task reset_instruments: :environment do
    scope = ENV.fetch("SCOPE", "failed")

    count = case scope
    when "all"
      Score.where.not(instruments_status: "pending").update_all(instruments_status: "pending", instruments: nil)
    when "failed"
      Score.instruments_failed.update_all(instruments_status: "pending")
    else
      abort "Unknown scope: #{scope}. Use SCOPE=all or SCOPE=failed"
    end

    puts "Reset #{count} scores to instruments_status=pending"
  end

  def print_instrument_stats
    puts
    puts "Database totals:"
    puts "  Normalized:     #{Score.instruments_normalized.count}"
    puts "  Not applicable: #{Score.instruments_not_applicable.count}"
    puts "  Failed:         #{Score.instruments_failed.count}"
    puts "  Pending:        #{Score.instruments_pending.count}"
  end
end
