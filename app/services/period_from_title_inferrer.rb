# frozen_string_literal: true

# Infers musical period from score metadata using LLM for failed composers.
#
# Usage:
#   result = PeriodFromTitleInferrer.new.infer(score)
#   result.period      # => "Renaissance" or "Romantic" or nil
#   result.success?    # => true (API call succeeded)
#   result.found?      # => true (period was identified)
#
class PeriodFromTitleInferrer
  Result = Data.define(:period, :confidence, :error) do
    def success? = error.nil?
    def found? = period.present?
  end

  PROMPT = <<~PROMPT
    You identify the musical period from sheet music metadata when the composer is unknown or traditional.

    Score metadata:
    - Title: %{title}
    - Composer: %{composer}
    - Genre: %{genre}
    - Description: %{description}
    - Language: %{language}
    - Current period (from source): %{current_period}

    What musical period is this piece from?

    Respond with JSON only:
    {"period": "Renaissance", "confidence": "high"}

    Valid periods (use exactly these):
    - Medieval
    - Renaissance
    - Baroque
    - Classical
    - Romantic
    - Late Romantic
    - Impressionist
    - 20th Century
    - Contemporary

    Rules:
    - Use title, language, and style hints to infer period
    - Latin titles often indicate Medieval/Renaissance
    - Traditional folk songs: identify by cultural origin and era
    - Spirituals: typically 19th/20th century
    - If current period seems correct, keep it (return same value)
    - If current period is wrong or unknown, return the correct period
    - If truly unknown/impossible to determine: return {"period": null, "confidence": "none"}
    - Confidence: "high" if clear indicators, "medium" if inferred, "low" if guessing, "none" if unknown
  PROMPT

  def initialize(client: nil)
    @client = client || LlmClient.new
  end

  def infer(score)
    response = @client.chat_json(build_prompt(score))

    Result.new(
      period: response["period"],
      confidence: response["confidence"],
      error: nil
    )
  rescue JSON::ParserError => e
    Result.new(period: nil, confidence: nil, error: "JSON parse error: #{e.message}")
  rescue LlmClient::Error => e
    Result.new(period: nil, confidence: nil, error: e.message)
  rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout => e
    Result.new(period: nil, confidence: nil, error: "Network timeout: #{e.message}")
  rescue StandardError => e
    Result.new(period: nil, confidence: nil, error: "Unexpected error: #{e.class} - #{e.message}")
  end

  private

  def build_prompt(score)
    format(PROMPT,
      title: score.title.to_s,
      composer: score.composer.to_s,
      genre: score.genre.presence || "unknown",
      description: score.description.to_s.truncate(200),
      language: score.language.presence || "unknown",
      current_period: score.period.presence || "unknown"
    )
  end
end
