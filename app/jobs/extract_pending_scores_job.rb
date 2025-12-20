# frozen_string_literal: true

# Enqueues Music21ExtractionJob for scores that haven't been processed.
#
# Usage:
#   ExtractPendingScoresJob.perform_later
#   ExtractPendingScoresJob.perform_later(limit: 100)
#   ExtractPendingScoresJob.perform_later(source: "pdmx")
#
class ExtractPendingScoresJob < ApplicationJob
  queue_as :default

  def perform(limit: 1000, source: nil)
    scores = Score.where(extraction_status: "pending")
    scores = scores.where(source: source) if source.present?
    scores = scores.where.not(mxl_path: [nil, "", "N/A"])
    scores = scores.limit(limit)

    scores.find_each do |score|
      Music21ExtractionJob.perform_later(score.id)
    end

    Rails.logger.info "[ExtractPendingScores] Enqueued #{scores.count} scores for extraction"
  end
end
