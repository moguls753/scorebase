class PurgeDeletedScoresJob < ApplicationJob
  queue_as :default

  RETENTION_DAYS = 100

  def perform
    # Find scores soft-deleted more than 100 days ago
    old_deleted_scores = Score.unscoped.deleted_before(RETENTION_DAYS.days.ago)
    count = old_deleted_scores.count

    if count > 0
      Rails.logger.info "[PurgeDeletedScoresJob] Permanently deleting #{count} scores deleted more than #{RETENTION_DAYS} days ago"
      old_deleted_scores.destroy_all
      Rails.logger.info "[PurgeDeletedScoresJob] Done"
    else
      Rails.logger.info "[PurgeDeletedScoresJob] No scores to purge"
    end
  end
end
