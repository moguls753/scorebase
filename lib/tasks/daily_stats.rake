namespace :daily_stats do
  desc "Re-aggregate DailyStat rows from retained Ahoy data (backfills columns added after a row was written)"
  task backfill: :environment do
    days = (ENV["DAYS"] || AggregateDailyStatsJob::RETENTION_DAYS).to_i
    dates = (days.days.ago.to_date..Date.current)

    dates.each { |date| DailyStat.aggregate_for!(date) }

    covered = DailyStat.where(date: dates).where.not(converting_visits: nil).count
    puts "Backfill done: #{dates.count} dates re-aggregated, " \
         "#{covered} rows now carry converting_visits."
  end
end
