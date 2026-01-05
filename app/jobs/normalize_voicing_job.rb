# frozen_string_literal: true

# Extracts voicing and instruments for vocal scores using LLM.
# Requires: has_vocal_status=normalized AND has_vocal=true
#
# Usage:
#   NormalizeVoicingJob.perform_later
#   NormalizeVoicingJob.perform_later(limit: 1000, batch_size: 3)
#
class NormalizeVoicingJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 3

  def perform(limit: 100, backend: :openai, model: nil, batch_size: BATCH_SIZE)
    scores = eligible_scores(limit).to_a
    return log_empty if scores.empty?

    log_start(scores.count, backend, batch_size)

    client = LlmClient.new(backend: backend, model: model)
    normalizer = VoicingNormalizer.new(client: client)
    stats = { normalized: 0, not_applicable: 0, failed: 0 }

    scores.each_slice(batch_size).with_index do |batch, batch_idx|
      results = normalizer.normalize(batch)

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
    Score.voicing_pending
         .has_vocal_normalized
         .where(has_vocal: true)
         .where.not(part_names: [nil, ""])
         .limit(limit)
  end

  def apply_result(score, result, stats, index)
    if result.found?
      score.update!(
        voicing: result.voicing,
        instruments: result.instruments,
        voicing_status: :normalized
      )
      stats[:normalized] += 1
      logger.info "[NormalizeVoicing] #{index}. #{score.title&.truncate(40)} -> #{result.voicing} / #{result.instruments} (#{result.confidence})"
    elsif result.success?
      score.update!(voicing_status: :not_applicable)
      stats[:not_applicable] += 1
      logger.info "[NormalizeVoicing] #{index}. #{score.title&.truncate(40)} -> N/A"
    else
      score.update!(voicing_status: :failed)
      stats[:failed] += 1
      logger.warn "[NormalizeVoicing] #{index}. #{score.title&.truncate(40)} -> FAILED: #{result.error}"
    end
  end

  def log_empty
    logger.info "[NormalizeVoicing] No eligible scores to process"
  end

  def log_start(count, backend, batch_size)
    logger.info "[NormalizeVoicing] Processing #{count} scores with #{backend} (batch_size: #{batch_size})"
  end

  def log_complete(stats)
    logger.info "[NormalizeVoicing] Complete: #{stats[:normalized]} normalized, #{stats[:not_applicable]} N/A, #{stats[:failed]} failed"
  end
end
