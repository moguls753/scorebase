# frozen_string_literal: true

# Infers genre using LLM.
# Requires: composer processed, instruments processed (any status except pending)
#
# Usage:
#   NormalizeGenresJob.perform_later
#   NormalizeGenresJob.perform_later(limit: 100, backend: :groq)
#
class NormalizeGenresJob < ApplicationJob
  queue_as :default

  def perform(limit: 100, backend: :groq)
    scores = eligible_scores(limit)

    log_start(scores.count, backend)
    return if scores.empty?

    client = LlmClient.new(backend: backend)
    inferrer = GenreInferrer.new(client: client)
    stats = { normalized: 0, not_applicable: 0, failed: 0 }

    scores.find_each.with_index do |score, i|
      result = inferrer.infer(score)

      if result.found?
        score.update!(genre: result.genre, genre_status: :normalized)
        stats[:normalized] += 1
        logger.info "[NormalizeGenres] #{i + 1}. #{score.title&.truncate(40)} -> #{result.genre}"
      elsif result.success?
        score.update!(genre_status: :not_applicable)
        stats[:not_applicable] += 1
        logger.info "[NormalizeGenres] #{i + 1}. #{score.title&.truncate(40)} -> N/A"
      else
        score.update!(genre_status: :failed)
        stats[:failed] += 1
        logger.warn "[NormalizeGenres] #{i + 1}. #{score.title&.truncate(40)} -> FAILED: #{result.error}"
      end

      sleep 0.1 if backend != :lmstudio
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

  def log_start(count, backend)
    logger.info "[NormalizeGenres] Processing #{count} scores with #{backend}"
    logger.info "[NormalizeGenres] Requires: composer processed, instruments processed"
  end

  def log_complete(stats)
    logger.info "[NormalizeGenres] Complete: #{stats[:normalized]} normalized, #{stats[:not_applicable]} N/A, #{stats[:failed]} failed"
  end
end
