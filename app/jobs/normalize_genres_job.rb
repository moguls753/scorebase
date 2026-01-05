# frozen_string_literal: true

# Infers genre using LLM in batches.
# Requires: composer processed, instruments processed (any status except pending)
#
# Usage:
#   NormalizeGenresJob.perform_later
#   NormalizeGenresJob.perform_later(limit: 1000, batch_size: 10)
#
class NormalizeGenresJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 10  # scores per API call

  def perform(limit: 100, backend: :openai, model: nil, batch_size: BATCH_SIZE)
    scores = eligible_scores(limit).to_a
    return log_empty if scores.empty?

    log_start(scores.count, backend, batch_size)

    client = LlmClient.new(backend: backend, model: model)
    inferrer = GenreInferrer.new(client: client)
    stats = { normalized: 0, not_applicable: 0, failed: 0 }

    scores.each_slice(batch_size).with_index do |batch, batch_idx|
      results = inferrer.infer(batch)

      results.each_with_index do |result, i|
        score = batch[i]
        index = batch_idx * batch_size + i + 1
        apply_result(score, result, stats, index)
      end

      sleep 0.1 unless backend == :lmstudio # Rate limiting (500 RPM allows ~8 req/s)
    end

    log_complete(stats)
  end

  private

  def eligible_scores(limit)
    Score.genre_pending
         .where.not(composer_status: "pending")
         .where.not(instruments_status: "pending")
         .where.not(title: [nil, ""])
         .limit(limit)
  end

  def apply_result(score, result, stats, index)
    if result.found?
      score.update!(genre: result.genre, genre_status: :normalized)
      stats[:normalized] += 1
      logger.info "[NormalizeGenres] #{index}. #{score.title&.truncate(40)} -> #{result.genre}"
    elsif result.success?
      score.update!(genre_status: :not_applicable)
      stats[:not_applicable] += 1
      logger.info "[NormalizeGenres] #{index}. #{score.title&.truncate(40)} -> N/A"
    else
      score.update!(genre_status: :failed)
      stats[:failed] += 1
      logger.warn "[NormalizeGenres] #{index}. #{score.title&.truncate(40)} -> FAILED: #{result.error}"
    end
  end

  def log_empty
    logger.info "[NormalizeGenres] No eligible scores to process"
  end

  def log_start(count, backend, batch_size)
    logger.info "[NormalizeGenres] Processing #{count} scores with #{backend} (batch_size: #{batch_size})"
  end

  def log_complete(stats)
    logger.info "[NormalizeGenres] Complete: #{stats[:normalized]} normalized, #{stats[:not_applicable]} N/A, #{stats[:failed]} failed"
  end
end
