class PurgeDeletedScoresJob < ApplicationJob
  queue_as :default

  RETENTION_DAYS = 100
  BATCH_SIZE = 500

  # Batched rather than destroy_all: that loaded every row and its dependents into
  # memory at once, which the 1 GB job container cannot hold once a partner
  # catalogue can contribute six figures of soft-deleted rows to a single run.
  # Each batch is its own transaction, so an interrupted run has still made progress.
  def perform
    scope = Score.unscoped.deleted_before(RETENTION_DAYS.days.ago)
    count = scope.count

    if count.zero?
      Rails.logger.info "[PurgeDeletedScoresJob] No scores to purge"
      return 0
    end

    Rails.logger.info "[PurgeDeletedScoresJob] Permanently deleting #{count} scores deleted more than #{RETENTION_DAYS} days ago"
    purged = 0
    scope.in_batches(of: BATCH_SIZE) do |batch|
      batch.destroy_all
      purged += batch.size
    end
    Rails.logger.info "[PurgeDeletedScoresJob] Done (#{purged})"
    purged
  end
end
