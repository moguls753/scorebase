# frozen_string_literal: true

namespace :infer do
  desc "Infer periods from title/metadata for failed composers. LIMIT=100 BACKEND=groq|gemini|lmstudio"
  task periods_from_title: :environment do
    limit = ENV.fetch("LIMIT", 100).to_i
    backend = ENV.fetch("BACKEND", "groq").to_sym

    InferPeriodsFromTitleJob.perform_now(limit: limit, backend: backend)
    print_period_stats
  end

  desc "Reset period status for failed composers. SCOPE=all|failed"
  task reset_periods_from_title: :environment do
    scope = ENV.fetch("SCOPE", "failed")

    count = case scope
    when "all"
      Score.where(composer_status: "failed").update_all(period_status: "pending", period: nil)
    when "failed"
      Score.where(composer_status: "failed", period_status: "failed").update_all(period_status: "pending")
    else
      abort "Unknown scope: #{scope}. Use SCOPE=all or SCOPE=failed"
    end

    puts "Reset #{count} scores to period_status=pending"
  end

  def print_period_stats
    puts
    puts "Database totals:"
    puts "  Normalized:     #{Score.period_normalized.count}"
    puts "  Not applicable: #{Score.period_not_applicable.count}"
    puts "  Failed:         #{Score.period_failed.count}"
    puts "  Pending:        #{Score.period_pending.count}"
  end
end
