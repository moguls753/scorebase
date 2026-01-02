# frozen_string_literal: true

# Infers musical period from title/metadata for scores that couldn't be normalized via composer lookup.
# This is the second stage of period normalization after NormalizePeriodsJob.
#
# Usage:
#   InferPeriodsFromTitleJob.perform_later
#   InferPeriodsFromTitleJob.perform_later(limit: 100, backend: :groq)
#
class InferPeriodsFromTitleJob < ApplicationJob
  queue_as :normalization

  def perform(limit: 100, backend: :groq, model: nil)
    scores = eligible_scores(limit)

    log_start(scores.count, backend, model)
    return if scores.empty?

    client = LlmClient.new(backend: backend, model: model)
    inferrer = PeriodFromTitleInferrer.new(client: client)
    stats = { normalized: 0, not_applicable: 0, failed: 0 }

    scores.find_each.with_index do |score, i|
      result = inferrer.infer(score)

      if result.found?
        score.update!(period: result.period, period_status: :normalized)
        stats[:normalized] += 1
        logger.info "[InferPeriods] #{i + 1}. #{score.title&.truncate(40)} -> #{result.period}"
      elsif result.success?
        score.update!(period_status: :not_applicable)
        stats[:not_applicable] += 1
        logger.info "[InferPeriods] #{i + 1}. #{score.title&.truncate(40)} -> N/A"
      else
        score.update!(period_status: :failed)
        stats[:failed] += 1
        logger.warn "[InferPeriods] #{i + 1}. #{score.title&.truncate(40)} -> FAILED: #{result.error}"
      end

      sleep 0.1 if backend != :lmstudio
    end

    log_complete(stats)
  end

  private

  def eligible_scores(limit)
    Score.period_pending
         .where.not(title: [nil, ""])
         .limit(limit)
  end

  def log_start(count, backend, model)
    logger.info "[InferPeriods] Processing #{count} scores with #{backend}#{model ? " (#{model})" : ''}"
    logger.info "[InferPeriods] Stage 2: inferring from title/metadata"
  end

  def log_complete(stats)
    logger.info "[InferPeriods] Complete: #{stats[:normalized]} normalized, #{stats[:not_applicable]} N/A, #{stats[:failed]} failed"
  end
end
