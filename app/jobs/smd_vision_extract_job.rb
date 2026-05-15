# frozen_string_literal: true

class SmdVisionExtractJob < ApplicationJob
  queue_as :default

  retry_on SmdVisionExtractor::RateLimitError, wait: :polynomially_longer, attempts: 6
  retry_on SmdVisionExtractor::ApiError,       wait: :polynomially_longer, attempts: 3

  rescue_from(SmdVisionExtractor::ApiError, SmdVisionExtractor::RateLimitError) do |error|
    score_id = arguments.first
    Score.where(id: score_id).update_all(extraction_status: "failed")
    Rails.logger.warn("[SmdVisionExtractJob] terminal failure score=#{score_id}: #{error.class}: #{error.message}")
  end

  def perform(score_id)
    score = Score.find_by(id: score_id)
    return unless score
    return if SmdVisionExtractor.already_processed?(score)

    result = SmdVisionExtractor.new(score).call

    case result.status
    when :rate_limited then raise SmdVisionExtractor::RateLimitError, result.error
    when :failed       then raise SmdVisionExtractor::ApiError,       result.error
    end

    Rails.logger.info("[SmdVisionExtractJob] score=#{score_id} status=#{result.status}")
  end
end
