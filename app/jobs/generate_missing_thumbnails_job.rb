# frozen_string_literal: true

# Batch job that finds scores needing thumbnails and enqueues individual jobs.
# Scheduled via config/recurring.yml for nightly processing.
class GenerateMissingThumbnailsJob < ApplicationJob
  queue_as :default

  def perform(source: nil, limit: nil)
    scope = Score.needing_thumbnail
    scope = scope.where(source: source) if source.present?
    scope = scope.limit(limit) if limit

    scope.find_each do |score|
      GenerateThumbnailJob.perform_later(score.id)
    end
  end
end
