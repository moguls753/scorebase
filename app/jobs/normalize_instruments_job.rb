# frozen_string_literal: true

# Extracts instruments from INSTRUMENTAL scores using LLM.
# Only runs on has_vocal=false scores (vocal scores use VoicingNormalizer).
# Requires: composer, period, and has_vocal all normalized.
#
# Usage:
#   NormalizeInstrumentsJob.perform_later
#   NormalizeInstrumentsJob.perform_later(limit: 1000, batch_size: 10)
#
class NormalizeInstrumentsJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 10  # scores per API call (same as period job)

  def perform(limit: 100, backend: :openai, model: nil, batch_size: BATCH_SIZE)
    scores = eligible_scores(limit).to_a
    return log_empty if scores.empty?

    log_start(scores.count, backend, batch_size)

    client = LlmClient.new(backend: backend, model: model)
    inferrer = InstrumentInferrer.new(client: client)
    stats = { normalized: 0, not_applicable: 0, failed: 0 }

    scores.each_slice(batch_size).with_index do |batch, batch_idx|
      results = inferrer.infer(batch)

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
    Score.instruments_pending
         .has_vocal_normalized
         .where(has_vocal: false)
         .where.not(composer_status: "pending")
         .where.not(period_status: "pending")
         .where.not(title: [nil, ""])
         .limit(limit)
  end

  def apply_result(score, result, stats, index)
    if result.found?
      score.assign_attributes(
        instruments: result.instruments,
        instruments_status: :normalized,
        voicing_status: :not_applicable
      )
      # Nullify chord_span if instrument isn't keyboard/harp (uses new instruments value)
      score.max_chord_span = nil unless score.chord_span_applicable?
      score.save!
      stats[:normalized] += 1
      logger.info "[NormalizeInstruments] #{index}. #{score.title&.truncate(40)} -> #{result.instruments}"
    elsif result.success?
      # Instrument unknown → chord_span not applicable either
      score.update!(
        instruments_status: :not_applicable,
        voicing_status: :not_applicable,
        max_chord_span: nil
      )
      stats[:not_applicable] += 1
      logger.info "[NormalizeInstruments] #{index}. #{score.title&.truncate(40)} -> N/A"
    else
      score.update!(instruments_status: :failed, voicing_status: :not_applicable)
      stats[:failed] += 1
      logger.warn "[NormalizeInstruments] #{index}. #{score.title&.truncate(40)} -> FAILED: #{result.error}"
    end
  end

  def log_empty
    logger.info "[NormalizeInstruments] No eligible scores to process"
  end

  def log_start(count, backend, batch_size)
    logger.info "[NormalizeInstruments] Processing #{count} scores with #{backend} (batch_size: #{batch_size})"
  end

  def log_complete(stats)
    logger.info "[NormalizeInstruments] Complete: #{stats[:normalized]} normalized, #{stats[:not_applicable]} N/A, #{stats[:failed]} failed"
  end
end
