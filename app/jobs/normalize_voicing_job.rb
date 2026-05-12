# frozen_string_literal: true

# Extracts voicing and instruments for vocal scores using LLM.
# Requires: has_vocal_status=normalized AND has_vocal=true
#
# Usage:
#   NormalizeVoicingJob.perform_later
#   NormalizeVoicingJob.perform_later(limit: 1000, batch_size: 3)
#   NormalizeVoicingJob.perform_later(limit: 10000, shard: 0, of: 3)  # parallel-safe slice
#
class NormalizeVoicingJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 3
  DB_FETCH_SIZE = 500

  def perform(limit: 100, backend: :openai, model: nil, batch_size: BATCH_SIZE, shard: nil, of: nil)
    total = eligible_scores(limit, shard: shard, of: of).count
    return log_empty if total.zero?

    log_start(total, backend, batch_size, shard: shard, of: of)

    client = LlmClient.new(backend: backend, model: model)
    normalizer = VoicingNormalizer.new(client: client)
    stats = { normalized: 0, not_applicable: 0, failed: 0 }
    index = 0

    eligible_scores(limit, shard: shard, of: of).find_in_batches(batch_size: DB_FETCH_SIZE) do |db_batch|
      db_batch.each_slice(batch_size) do |llm_batch|
        results = normalizer.normalize(llm_batch)

        results.each_with_index do |result, i|
          score = llm_batch[i]
          index += 1
          apply_result(score, result, stats, index)
        end

        sleep 0.1 # Rate limiting (500 RPM allows ~8 req/s)
      end
    end

    log_complete(stats)
  end

  private

  def eligible_scores(limit, shard: nil, of: nil)
    scope = Score.voicing_pending
                 .has_vocal_normalized
                 .where(has_vocal: true)
                 .where.not(part_names: [nil, ""])
    scope = scope.where("id % ? = ?", of, shard) if shard && of
    scope.limit(limit)
  end

  def apply_result(score, result, stats, index)
    if result.found?
      score.update!(
        voicing: result.voicing&.delete(" "),
        instruments: result.instruments,
        voicing_status: :normalized,
        instruments_status: :normalized
      )
      stats[:normalized] += 1
      logger.info "[NormalizeVoicing] #{index}. #{score.title&.truncate(40)} -> #{result.voicing} / #{result.instruments} (#{result.confidence})"
    elsif result.success?
      score.update!(voicing_status: :not_applicable, instruments_status: :not_applicable)
      stats[:not_applicable] += 1
      logger.info "[NormalizeVoicing] #{index}. #{score.title&.truncate(40)} -> N/A"
    else
      score.update!(voicing_status: :failed, instruments_status: :failed)
      stats[:failed] += 1
      logger.warn "[NormalizeVoicing] #{index}. #{score.title&.truncate(40)} -> FAILED: #{result.error}"
    end
  end

  def log_empty
    logger.info "[NormalizeVoicing] No eligible scores to process"
  end

  def log_start(count, backend, batch_size, shard: nil, of: nil)
    shard_tag = (shard && of) ? " [shard #{shard}/#{of}]" : ""
    logger.info "[NormalizeVoicing]#{shard_tag} Processing #{count} scores with #{backend} (batch_size: #{batch_size})"
  end

  def log_complete(stats)
    logger.info "[NormalizeVoicing] Complete: #{stats[:normalized]} normalized, #{stats[:not_applicable]} N/A, #{stats[:failed]} failed"
  end
end
