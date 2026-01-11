# frozen_string_literal: true

# Validates has_vocal field using LLM analysis of all available signals.
# Requires: composer and period processed (any status except pending)
#
# Usage:
#   NormalizeHasVocalJob.perform_later
#   NormalizeHasVocalJob.perform_later(limit: 1000, batch_size: 10)
#
class NormalizeHasVocalJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 10  # scores per API call

  def perform(limit: 100, backend: :openai, model: nil, batch_size: BATCH_SIZE)
    scores = eligible_scores(limit).to_a
    return log_empty if scores.empty?

    log_start(scores.count, backend, batch_size)

    client = LlmClient.new(backend: backend, model: model)
    detector = VocalDetector.new(client: client)
    stats = { normalized: 0, failed: 0 }

    scores.each_slice(batch_size).with_index do |batch, batch_idx|
      results = detector.detect(batch)

      results.each_with_index do |result, i|
        score = batch[i]
        index = batch_idx * batch_size + i + 1
        apply_result(score, result, stats, index)
      end

      sleep 0.1 # Rate limiting (500 RPM allows ~8 req/s)
    end

    log_complete(stats)
  end

  private

  def eligible_scores(limit)
    Score.has_vocal_pending
         .where(extraction_status: "extracted")
         .where.not(composer_status: "pending")
         .where.not(period_status: "pending")
         .limit(limit)
  end

  def apply_result(score, result, stats, index)
    if result.success?
      score.assign_attributes(has_vocal: result.has_vocal, has_vocal_status: :normalized)
      # Nullify chord_span for vocal scores (not applicable)
      score.max_chord_span = nil if result.has_vocal
      score.save!
      stats[:normalized] += 1
      logger.info "[NormalizeHasVocal] #{index}. #{score.title&.truncate(40)} -> #{result.has_vocal} (#{result.confidence})"
    else
      score.update!(has_vocal_status: :failed)
      stats[:failed] += 1
      logger.warn "[NormalizeHasVocal] #{index}. #{score.title&.truncate(40)} -> FAILED: #{result.error}"
    end
  end

  def log_empty
    logger.info "[NormalizeHasVocal] No eligible scores to process"
  end

  def log_start(count, backend, batch_size)
    logger.info "[NormalizeHasVocal] Processing #{count} scores with #{backend} (batch_size: #{batch_size})"
  end

  def log_complete(stats)
    logger.info "[NormalizeHasVocal] Complete: #{stats[:normalized]} normalized, #{stats[:failed]} failed"
  end
end
