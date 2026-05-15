# frozen_string_literal: true

# Per-score wrapper around SmdStatusNormalizer. Enqueue via
# `rake smd:normalize:status LIMIT=N`. Idempotent: skips already-normalized
# scores (and short-circuits when source != smd or vision hasn't run).
class SmdNormalizeStatusJob < ApplicationJob
  queue_as :default

  def perform(score_id)
    score = Score.find_by(id: score_id)
    return unless score
    return unless score.source == "smd"

    result = SmdStatusNormalizer.new(score).call
    Rails.logger.info(
      "[SmdNormalizeStatusJob] score=#{score_id} status=#{result.status}" \
      "#{result.reason ? " reason=#{result.reason}" : ""}"
    )
  end
end
