# frozen_string_literal: true

# Batch job that finds external scores needing PDF sync and enqueues individual jobs.
# Scheduled via config/recurring.yml for nightly processing.
class SyncMissingPdfsJob < ApplicationJob
  queue_as :default

  def perform(source: nil, limit: nil)
    scope = Score.needing_pdf_sync
    scope = scope.where(source: source) if source.present?
    scope = scope.limit(limit) if limit

    scope.find_each do |score|
      SyncPdfJob.perform_later(score.id)
    end
  end
end
