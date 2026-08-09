namespace :daily_stats do
  desc "Re-aggregate DailyStat rows from retained Ahoy data (backfills columns added after a row was written)"
  task backfill: :environment do
    days = (ENV["DAYS"] || AggregateDailyStatsJob::RETENTION_DAYS).to_i
    dates = (days.days.ago.to_date..Date.current)

    dates.each { |date| DailyStat.aggregate_for!(date) }

    scoped = DailyStat.where(date: dates)
    puts "Backfill done: #{dates.count} dates re-aggregated, " \
         "#{scoped.measured.count} carry human metrics " \
         "(#{DailyStat::REFERRER_CAPTURE_STARTED_ON} onward)."
  end
end
