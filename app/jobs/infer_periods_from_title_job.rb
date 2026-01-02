# frozen_string_literal: true

# Infers musical period from title/metadata for scores that couldn't be normalized via composer lookup.
# This is the second stage of period normalization after NormalizePeriodsJob.
#
# Usage:
#   InferPeriodsFromTitleJob.perform_later
#   InferPeriodsFromTitleJob.perform_later(limit: 1000, batch_size: 5)
#
class InferPeriodsFromTitleJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 5

  def perform(limit: 100, backend: :openai, model: nil, batch_size: BATCH_SIZE)
    scores = eligible_scores(limit).to_a
    return log_empty if scores.empty?

    log_start(scores.count, backend, batch_size)

    client = LlmClient.new(backend: backend, model: model)
    inferrer = PeriodFromTitleInferrer.new(client: client)
    stats = { normalized: 0, not_applicable: 0, failed: 0 }

    scores.each_slice(batch_size).with_index do |batch, batch_idx|
      results = inferrer.infer(batch)

      results.each_with_index do |result, i|
        score = batch[i]
        index = batch_idx * batch_size + i + 1
        apply_result(score, result, stats, index)
      end

      sleep 0.2 # Rate limiting
    end

    log_complete(stats)
  end

  private

  def eligible_scores(limit)
    Score.period_pending
         .where.not(title: [nil, ""])
         .limit(limit)
  end

  def apply_result(score, result, stats, index)
    if result.found?
      score.update!(period: result.period, period_status: :normalized)
      stats[:normalized] += 1
      logger.info "[InferPeriods] #{index}. #{score.title&.truncate(40)} -> #{result.period}"
    elsif result.success?
      score.update!(period_status: :not_applicable)
      stats[:not_applicable] += 1
      logger.info "[InferPeriods] #{index}. #{score.title&.truncate(40)} -> N/A"
    else
      score.update!(period_status: :failed)
      stats[:failed] += 1
      logger.warn "[InferPeriods] #{index}. #{score.title&.truncate(40)} -> FAILED: #{result.error}"
    end
  end

  def log_empty
    logger.info "[InferPeriods] No eligible scores to process"
  end

  def log_start(count, backend, batch_size)
    logger.info "[InferPeriods] Processing #{count} scores with #{backend} (batch_size: #{batch_size})"
  end

  def log_complete(stats)
    logger.info "[InferPeriods] Complete: #{stats[:normalized]} normalized, #{stats[:not_applicable]} N/A, #{stats[:failed]} failed"
  end
end
