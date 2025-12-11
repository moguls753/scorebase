class GeneratePreviewJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: 1.minute, attempts: 3

  def perform(score_id)
    score = Score.find_by(id: score_id)
    return unless score

    generator = ThumbnailGenerator.new(score)
    generator.generate_preview!
  end
end
