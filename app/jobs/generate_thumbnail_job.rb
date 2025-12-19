# frozen_string_literal: true

# Generates and caches thumbnail for a single score.
# Delegates to Score#generate_thumbnail (from Thumbnailable concern).
class GenerateThumbnailJob < ApplicationJob
  queue_as :thumbnails

  retry_on StandardError, wait: 1.minute, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(score_id)
    Score.find(score_id).generate_thumbnail
  end
end
