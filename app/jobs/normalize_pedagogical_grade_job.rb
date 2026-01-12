# frozen_string_literal: true

# Infers pedagogical grade for known pieces using LLM.
# Targets pieces where algorithm difficulty may be misleading:
# - computed_difficulty 1-3 (algorithm says easy-to-moderate)
# - Known composer (composer_status: normalized)
# - Confirmed instrumental (has_vocal_status: normalized, has_vocal: false)
# - Has instruments metadata
#
# Usage:
#   NormalizePedagogicalGradeJob.perform_later
#   NormalizePedagogicalGradeJob.perform_later(limit: 1000, batch_size: 5)
#
class NormalizePedagogicalGradeJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 5

  def perform(limit: 100, backend: :openai, model: nil, batch_size: BATCH_SIZE)
    scores = eligible_scores(limit).to_a
    return log_empty if scores.empty?

    log_start(scores.count, backend, batch_size)

    client = LlmClient.new(backend: backend, model: model)
    inferrer = PedagogicalGradeInferrer.new(client: client)
    stats = { normalized: 0, not_applicable: 0, failed: 0 }

    scores.each_slice(batch_size).with_index do |batch, batch_idx|
      results = inferrer.infer(batch)

      results.each_with_index do |result, i|
        score = batch[i]
        index = batch_idx * batch_size + i + 1
        apply_result(score, result, stats, index)
      end

      sleep 0.1 unless backend == :lmstudio
    end

    log_complete(stats)
  end

  private

  # High priority: algorithm says easy but likely wrong for pedagogical pieces
  def eligible_scores(limit)
    Score.grade_pending
         .where(computed_difficulty: [1, 2, 3])   # algorithm says easy-to-moderate
         .where(composer_status: :normalized)      # known composer
         .where(has_vocal_status: :normalized)     # vocal detection completed
         .where(has_vocal: false)                  # instrumental only (vocal grades differ)
         .where.not(instruments: [nil, ""])        # has instrument info
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

  def apply_result(score, result, stats, index)
    if result.found?
      score.update!(
        pedagogical_grade: result.grade,
        pedagogical_grade_de: result.grade_de,
        grade_status: :normalized,
        grade_source: "llm"
      )
      stats[:normalized] += 1
      logger.info "[NormalizePedagogicalGrade] #{index}. #{score.title&.truncate(40)} -> #{result.grade} (#{result.grade_de})"
    elsif result.success?
      # LLM returned successfully but doesn't know this piece
      score.update!(grade_status: :not_applicable, grade_source: "llm")
      stats[:not_applicable] += 1
      logger.info "[NormalizePedagogicalGrade] #{index}. #{score.title&.truncate(40)} -> unknown piece"
    else
      score.update!(grade_status: :failed)
      stats[:failed] += 1
      logger.warn "[NormalizePedagogicalGrade] #{index}. #{score.title&.truncate(40)} -> FAILED: #{result.error}"
    end
  end

  def log_empty
    logger.info "[NormalizePedagogicalGrade] No eligible scores to process"
  end

  def log_start(count, backend, batch_size)
    logger.info "[NormalizePedagogicalGrade] Processing #{count} scores with #{backend} (batch_size: #{batch_size})"
  end

  def log_complete(stats)
    logger.info "[NormalizePedagogicalGrade] Complete: #{stats[:normalized]} normalized, #{stats[:not_applicable]} unknown, #{stats[:failed]} failed"
  end
end
