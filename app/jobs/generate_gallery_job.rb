# frozen_string_literal: true

# Generates gallery pages for a single score.
# Delegates to Score#generate_gallery (from Galleried concern).
class GenerateGalleryJob < ApplicationJob
  queue_as :galleries

  # Longer retry delay - PDF processing is resource intensive
  retry_on StandardError, wait: 2.minutes, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(score_id)
    Score.find(score_id).generate_gallery
  end
end
