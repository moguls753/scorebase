class GenerateThumbnailJob < ApplicationJob
  queue_as :thumbnails

  retry_on StandardError, wait: 1.minute, attempts: 3

  def perform(score_id)
    score = Score.find_by(id: score_id)
    return unless score

    ThumbnailGenerator.new(score).generate
  end
end
