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
    count = scores.count

    logger.info "[NormalizePeriods] Processing #{count} scores"
    return if count.zero?

    # Group scores by inferred period for batch updates
    by_period = Hash.new { |h, k| h[k] = [] }

    scores.find_each do |score|
      period = PeriodInferrer.infer(score.composer)
      by_period[period] << score.id
    end

    stats = { normalized: 0, not_applicable: 0 }

    by_period.each do |period, ids|
      if period.present?
        Score.where(id: ids).update_all(period: period, period_status: "normalized")
        stats[:normalized] += ids.size
      else
        Score.where(id: ids).update_all(period_status: "not_applicable")
        stats[:not_applicable] += ids.size
      end
    end

    logger.info "[NormalizePeriods] Complete: #{stats[:normalized]} normalized, #{stats[:not_applicable]} not applicable"
  end

  private

  def eligible_scores(limit)
    Score.period_pending
         .composer_normalized
         .where.not(composer: [nil, ""])
         .limit(limit)
  end
end
