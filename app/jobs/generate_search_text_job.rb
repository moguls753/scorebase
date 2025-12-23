# frozen_string_literal: true

# Generates search_text for RAG indexing using LLM.
# Processes scores that are ready_for_rag? and updates rag_status.
#
# Usage:
#   GenerateSearchTextJob.perform_later
#   GenerateSearchTextJob.perform_later(limit: 100, backend: :groq)
#   GenerateSearchTextJob.perform_later(force: true)  # regenerate already-templated
#
class GenerateSearchTextJob < ApplicationJob
  queue_as :rag

  def perform(limit: 100, backend: :groq, force: false)
    scores = eligible_scores(limit, force: force).to_a

    log_start(scores.size, backend, force)
    return if scores.empty?

    client = LlmClient.new(backend: backend)
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
        reason = result.error || result.issues.join(", ")
        logger.warn "[GenerateSearchText] #{i + 1}. #{score.title&.truncate(40)} ✗ #{reason}"
      end

      sleep 0.1 if backend != :lmstudio
    end

    log_complete(stats)
  end

  private

  def eligible_scores(limit, force:)
    scope = if force
              Score.where(rag_status: %w[ready templated])
            else
              Score.rag_ready
            end
    scope.limit(limit)
  end

  def log_start(count, backend, force)
    mode = force ? "(force regenerate)" : "(new only)"
    logger.info "[GenerateSearchText] Processing #{count} scores with #{backend} #{mode}"
  end

  def log_complete(stats)
    logger.info "[GenerateSearchText] Complete: #{stats[:templated]} templated, #{stats[:failed]} failed"
  end
end
