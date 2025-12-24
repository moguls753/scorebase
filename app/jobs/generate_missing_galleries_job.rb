# frozen_string_literal: true

# Batch job that finds scores needing galleries and enqueues individual jobs.
# Scheduled via config/recurring.yml for nightly processing.
class GenerateMissingGalleriesJob < ApplicationJob
  queue_as :default

  def perform(source: nil, limit: 2000)
    scope = Score.needing_gallery
    scope = scope.where(source: source) if source.present?
    scope = scope.limit(limit) if limit

    scope.find_each do |score|
      GenerateGalleryJob.perform_later(score.id)
    end
  end
end
