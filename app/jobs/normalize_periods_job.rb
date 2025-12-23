# frozen_string_literal: true

# Infers musical period from normalized composer name.
# Requires: composer_normalized (hash lookup by exact name)
#
# Usage:
#   NormalizePeriodsJob.perform_later
#   NormalizePeriodsJob.perform_later(limit: 5000)
#
class NormalizePeriodsJob < ApplicationJob
  queue_as :normalization

  def perform(limit: 1000)
    scores = eligible_scores(limit)

    log_start(scores.count)
    return if scores.empty?

    stats = { normalized: 0, not_applicable: 0 }

    scores.find_each do |score|
      period = PeriodInferrer.infer(score.composer)

      if period.present?
        score.update!(period: period, period_status: :normalized)
        stats[:normalized] += 1
      else
        score.update!(period_status: :not_applicable)
        stats[:not_applicable] += 1
      end
    end

    log_complete(stats)
  end

  private

  def eligible_scores(limit)
    Score.period_pending
         .composer_normalized
         .where.not(composer: [nil, ""])
         .limit(limit)
  end

  def log_start(count)
    logger.info "[NormalizePeriods] Processing #{count} scores"
    logger.info "[NormalizePeriods] Requires: composer_normalized"
  end

  def log_complete(stats)
    logger.info "[NormalizePeriods] Complete: #{stats[:normalized]} normalized, #{stats[:not_applicable]} not applicable"
  end
end
