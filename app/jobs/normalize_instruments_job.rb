# frozen_string_literal: true

# Infers instruments using LLM.
# Requires: composer processed (any status except pending)
#
# Usage:
#   NormalizeInstrumentsJob.perform_later
#   NormalizeInstrumentsJob.perform_later(limit: 100, backend: :groq)
#
class NormalizeInstrumentsJob < ApplicationJob
  queue_as :normalization

  def perform(limit: 100, backend: :groq)
    scores = eligible_scores(limit)

    log_start(scores.count, backend)
    return if scores.empty?

    client = LlmClient.new(backend: backend)
    inferrer = InstrumentInferrer.new(client: client)
    stats = { normalized: 0, not_applicable: 0, failed: 0 }

    scores.find_each.with_index do |score, i|
      result = inferrer.infer(score)

      if result.found?
        score.update!(instruments: result.instruments, instruments_status: :normalized)
        stats[:normalized] += 1
        logger.info "[NormalizeInstruments] #{i + 1}. #{score.title&.truncate(40)} -> #{result.instruments}"
      elsif result.success?
        score.update!(instruments_status: :not_applicable)
        stats[:not_applicable] += 1
        logger.info "[NormalizeInstruments] #{i + 1}. #{score.title&.truncate(40)} -> N/A"
      else
        score.update!(instruments_status: :failed)
        stats[:failed] += 1
        logger.warn "[NormalizeInstruments] #{i + 1}. #{score.title&.truncate(40)} -> FAILED: #{result.error}"
      end

      sleep 0.1 if backend != :lmstudio
    end

    log_complete(stats)
  end

  private

  def eligible_scores(limit)
    Score.instruments_pending
         .where.not(composer_status: "pending")
         .where.not(title: [nil, ""])
         .limit(limit)
  end

  def log_start(count, backend)
    logger.info "[NormalizeInstruments] Processing #{count} scores with #{backend}"
    logger.info "[NormalizeInstruments] Requires: composer processed"
  end

  def log_complete(stats)
    logger.info "[NormalizeInstruments] Complete: #{stats[:normalized]} normalized, #{stats[:not_applicable]} N/A, #{stats[:failed]} failed"
  end
end
