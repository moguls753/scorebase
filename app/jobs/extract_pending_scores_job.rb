# frozen_string_literal: true

# Extracts musical features from pending scores using music21.
#
# Usage:
#   ExtractPendingScoresJob.perform_later
#   ExtractPendingScoresJob.perform_later(limit: 100)
#
class ExtractPendingScoresJob < ApplicationJob
  queue_as :extractions

  def perform(limit: 100)
    scores = Score.extraction_pending
                  .where.not(mxl_path: [nil, "", "N/A"])
                  .limit(limit)
                  .to_a

    logger.info "[ExtractPendingScores] Processing #{scores.size} scores"
    return if scores.empty?

    stats = { extracted: 0, failed: 0 }

    scores.each_with_index do |score, i|
      Music21Extractor.extract(score)
      stats[:extracted] += 1
      logger.info "[ExtractPendingScores] #{i + 1}. #{score.title&.truncate(40)} ✓"
    rescue Music21Extractor::Error => e
      stats[:failed] += 1
      logger.warn "[ExtractPendingScores] #{i + 1}. #{score.title&.truncate(40)} ✗ #{e.message}"
    end

    logger.info "[ExtractPendingScores] Complete: #{stats[:extracted]} extracted, #{stats[:failed]} failed"
  end
end
