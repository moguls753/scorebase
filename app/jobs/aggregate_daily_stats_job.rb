class AggregateDailyStatsJob < ApplicationJob
  queue_as :default

  RETENTION_DAYS = 30

  def perform
    DailyStat.aggregate_for!(Date.current)
    DailyStat.aggregate_for!(Date.current - 1)

    cutoff = RETENTION_DAYS.days.ago
    deleted_events = prune_in_batches(Ahoy::Event,  :time,       cutoff)
    deleted_visits = prune_in_batches(Ahoy::Visit, :started_at, cutoff)
    if deleted_events.positive? || deleted_visits.positive?
      logger.info "[AggregateDailyStats] pruned events=#{deleted_events} visits=#{deleted_visits} (older than #{cutoff.to_date})"
    end
  end

  private

  def prune_in_batches(model, time_col, cutoff, batch_size: 5000)
    total = 0
    loop do
      n = model.where(model.arel_table[time_col].lt(cutoff)).limit(batch_size).delete_all
      total += n
      break if n < batch_size
    end
    total
  end
end
