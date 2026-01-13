# frozen_string_literal: true

# Infers pedagogical grade for known pieces using LLM.
#
# Pipeline behavior:
# - Propagates upstream failures (composer_status: failed → grade not_applicable)
# - Processes eligible scores in batches
# - Retries "unknown" results once with single query (reduces batch noise)
#
# Scope: All scores with known composer (~51K scores)
# - composer_status: normalized
# - Has title
#
# Model: Groq Llama 4 Maverick (90% accuracy, ~$2.63 for full run)
#
# Usage:
#   NormalizePedagogicalGradeJob.perform_later
#   NormalizePedagogicalGradeJob.perform_later(limit: 1000)
#
class NormalizePedagogicalGradeJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 2

  GROQ_MODEL = "meta-llama/llama-4-maverick-17b-128e-instruct"

  def perform(limit: 100, backend: :groq, model: GROQ_MODEL, batch_size: BATCH_SIZE)
    propagate_upstream_failures

    scores = eligible_scores(limit).to_a
    return log_empty if scores.empty?

    log_start(scores.count, backend, batch_size)

    @client = LlmClient.new(backend: backend, model: model)
    @inferrer = PedagogicalGradeInferrer.new(client: @client)
    @backend = backend
    @stats = { normalized: 0, not_applicable: 0, failed: 0 }

    scores.each_slice(batch_size).with_index do |batch, batch_idx|
      results = @inferrer.infer(batch)

      results.each_with_index do |result, i|
        score = batch[i]
        index = batch_idx * batch_size + i + 1
        apply_result(score, result, index)
      end

      sleep 0.1 unless backend == :lmstudio
    end

    log_complete
  end

  private

  # Scores eligible for LLM grade normalization:
  # - Known composer (composer_status: normalized)
  # - Has title (for LLM to identify the piece)
  def eligible_scores(limit)
    Score.grade_pending
         .where(composer_status: :normalized)
         .where.not(title: [nil, ""])
         .order(prioritized_order)
         .limit(limit)
  end

  # Prioritize pedagogical title patterns (etudes, sonatinas, etc.)
  def prioritized_order
    Arel.sql(<<~SQL.squish)
      CASE
        WHEN title LIKE '%Etude%' OR title LIKE '%Study%' OR title LIKE '%Étude%' THEN 1
        WHEN title LIKE '%Sonatina%' OR title LIKE '%Sonatine%' THEN 2
        WHEN title LIKE '%Invention%' THEN 3
        WHEN title LIKE '%Op.%' OR title LIKE '%BWV%' OR title LIKE '%WoO%' THEN 4
        ELSE 5
      END, id
    SQL
  end

  def apply_result(score, result, index)
    if result.found?
      save_grade(score, result, index)
    elsif result.success?
      # LLM said "unknown" - retry once with single query (reduces batch noise)
      retry_single(score, index)
    else
      mark_failed(score, result.error, index)
    end
  end

  def retry_single(score, index)
    sleep 0.1 unless @backend == :lmstudio
    result = @inferrer.infer([score]).first

    if result.found?
      save_grade(score, result, index, retried: true)
    elsif result.success?
      # LLM said unknown on retry too - genuinely unknown piece
      mark_not_applicable(score, index)
    else
      # API error on retry - mark failed so it can be retried later
      mark_failed(score, result.error, index)
    end
  end

  def save_grade(score, result, index, retried: false)
    score.update!(
      pedagogical_grade: result.grade,
      pedagogical_grade_de: result.grade_de,
      grade_status: :normalized,
      grade_source: "llm"
    )
    @stats[:normalized] += 1
    retry_note = retried ? " (retried)" : ""
    logger.info "[NormalizePedagogicalGrade] #{index}. #{score.title&.truncate(40)} -> #{result.grade}#{retry_note}"
  end

  def mark_not_applicable(score, index)
    score.update!(grade_status: :not_applicable, grade_source: "llm")
    @stats[:not_applicable] += 1
    logger.info "[NormalizePedagogicalGrade] #{index}. #{score.title&.truncate(40)} -> unknown piece"
  end

  def mark_failed(score, error, index)
    score.update!(grade_status: :failed)
    @stats[:failed] += 1
    logger.warn "[NormalizePedagogicalGrade] #{index}. #{score.title&.truncate(40)} -> FAILED: #{error}"
  end

  # Propagate upstream failures: if composer normalization failed,
  # grade normalization can't succeed (no way to identify the piece)
  def propagate_upstream_failures
    count = Score.where(composer_status: :failed, grade_status: :pending)
                 .update_all(grade_status: :not_applicable, grade_source: "no_composer")
    logger.info "[NormalizePedagogicalGrade] Propagated #{count} composer failures" if count > 0
  end

  def log_empty
    logger.info "[NormalizePedagogicalGrade] No eligible scores to process"
  end

  def log_start(count, backend, batch_size)
    logger.info "[NormalizePedagogicalGrade] Processing #{count} scores with #{backend} (batch_size: #{batch_size})"
  end

  def log_complete
    parts = ["#{@stats[:normalized]} normalized", "#{@stats[:not_applicable]} unknown"]
    parts << "#{@stats[:failed]} failed" if @stats[:failed] > 0
    logger.info "[NormalizePedagogicalGrade] Complete: #{parts.join(', ')}"
  end
end
