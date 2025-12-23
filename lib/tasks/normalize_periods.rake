# frozen_string_literal: true

namespace :normalize do
  desc "Infer periods from composer names. LIMIT=1000. Requires: composer_normalized"
  task periods: :environment do
    limit = ENV.fetch("LIMIT", 1000).to_i
    NormalizePeriodsJob.perform_now(limit: limit)
    print_period_stats
  end

  desc "Reset period normalization. SCOPE=all|not_applicable"
  task reset_periods: :environment do
    scope = ENV.fetch("SCOPE", "not_applicable")

    count = case scope
    when "all"
      Score.where.not(period_status: "pending").update_all(period_status: "pending", period: nil)
    when "not_applicable"
      Score.period_not_applicable.update_all(period_status: "pending")
    else
      abort "Unknown scope: #{scope}. Use SCOPE=all or SCOPE=not_applicable"
    end

    puts "Reset #{count} scores to period_status=pending"
  end

  def print_period_stats
    puts
    puts "Database totals:"
    puts "  Normalized:     #{Score.period_normalized.count}"
    puts "  Not applicable: #{Score.period_not_applicable.count}"
    puts "  Pending:        #{Score.period_pending.count}"
  end
end
