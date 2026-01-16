# frozen_string_literal: true

# Generates search_text for RAG indexing using LLM.
# Processes scores that are ready_for_rag? and updates rag_status.
#
# Usage:
#   GenerateSearchTextJob.perform_later
#   GenerateSearchTextJob.perform_later(limit: 100, backend: :groq)
#   GenerateSearchTextJob.perform_later(model: "llama-3.1-8b-instant")
#   GenerateSearchTextJob.perform_later(scope: "priority")  # balanced instrument sampling
#   GenerateSearchTextJob.perform_later(force: true)        # regenerate already-templated
#
class GenerateSearchTextJob < ApplicationJob
  queue_as :rag

  # Default model: llama-4-scout produces better variety than llama-3.1-8b
  # (less template repetition, better embedding differentiation for RAG)
  DEFAULT_MODEL = "meta-llama/llama-4-scout-17b-16e-instruct"

  # Priority scope for testing - balanced across instruments, composers AND grades
  # Ensures we get beginner through advanced pieces for search testing
  PRIORITY_CATEGORIES = [
    "voicing = 'SATB'",
    "instruments LIKE '%Guitar%'",
    "instruments LIKE '%Piano%'",
    "(composer LIKE '%Bach%' OR composer LIKE '%Mozart%' OR composer LIKE '%Handel%')",
    "pedagogical_grade LIKE 'Grade 1%' OR pedagogical_grade LIKE 'Grade 2%'",  # Beginner
    "pedagogical_grade LIKE 'Grade 3%'",                                        # Intermediate
    "pedagogical_grade LIKE 'Grade 6%' OR pedagogical_grade LIKE 'Grade 7%'"   # Advanced
  ].freeze

  def perform(limit: 100, backend: :groq, model: DEFAULT_MODEL, scope: nil, force: false)
    scores = eligible_scores(limit, scope: scope, force: force).to_a

    log_start(scores.size, backend, model, scope, force)
    return if scores.empty?

    client = LlmClient.new(backend: backend, model: model)
    generator = SearchTextGenerator.new(client: client)
    stats = { templated: 0, failed: 0 }

    scores.each_with_index do |score, i|
      result = generator.generate(score)

      if result.success?
        score.update!(
          search_text: result.description,
          search_text_generated_at: Time.current,
          rag_status: :templated
        )
        stats[:templated] += 1
        logger.info "[GenerateSearchText] #{i + 1}. #{score.title&.truncate(40)} ✓"
      else
        score.update!(rag_status: :failed)
        stats[:failed] += 1
        begin
          reason = result.error || result.issues.join(", ")
          logger.warn "[GenerateSearchText] #{i + 1}. #{score.title&.truncate(40)} ✗ #{reason}"
        rescue Encoding::CompatibilityError
          logger.warn "[GenerateSearchText] #{i + 1}. (id:#{score.id}) ✗ (encoding error in log)"
        end
      end

      sleep 0.1 if backend != :lmstudio
    end

    log_complete(stats)
  end

  private

  def eligible_scores(limit, scope:, force:)
    base = if force
      Score.where(rag_status: %w[ready templated])
    else
      Score.rag_ready
    end

    if scope.to_s == "priority"
      # Balanced sampling: distribute limit evenly across categories
      per_category = (limit.to_f / PRIORITY_CATEGORIES.size).ceil
      ids = PRIORITY_CATEGORIES.flat_map do |cat_sql|
        base.where(cat_sql).limit(per_category).pluck(:id)
      end.uniq.first(limit)

      Score.where(id: ids)
    else
      base.limit(limit)
    end
  end

  def log_start(count, backend, model, scope, force)
    mode = force ? "(force regenerate)" : "(new only)"
    model_name = model.split("/").last  # "meta-llama/llama-4-scout..." → "llama-4-scout..."
    scope_info = scope.present? ? "[#{scope}] " : ""
    logger.info "[GenerateSearchText] #{scope_info}Processing #{count} scores with #{backend}/#{model_name} #{mode}"
  end

  def log_complete(stats)
    logger.info "[GenerateSearchText] Complete: #{stats[:templated]} templated, #{stats[:failed]} failed"
  end
end
