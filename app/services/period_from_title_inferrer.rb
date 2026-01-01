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
    - Medieval (before 1400)
    - Renaissance (1400-1600)
    - Baroque (1600-1750)
    - Classical (1750-1820)
    - Romantic (1820-1900)
    - Late Romantic (1880-1920)
    - Impressionist (1890-1920)
    - 20th Century (1900-2000)
    - Contemporary (2000+)

    CRITICAL RULES - READ CAREFULLY:
    - Return null for MOST pieces - be very conservative
    - ONLY return a period if you have SPECIFIC factual knowledge about when this exact piece was composed
    - "Sweet Child O Mine" by Guns N' Roses (1987) → "Contemporary"
    - "Jingle Bells" by James Lord Pierpont (1857) → "Romantic"
    - "santa baby" by Joan Javits (1953) → "20th Century"
    - If you know the composer name or year from your training: use it
    - If you only recognize the title vaguely: return null
    - If it "sounds like" a hymn/folk song but you don't know WHEN: return null
    - DO NOT guess periods based on title style, language, or genre
    - When in doubt: return null

    Test yourself:
    - "Ave maris stella" → Do you know the century? If yes: Medieval. If no: null
    - "random church hymn title" → Don't know when? → null
    - Generic title like "[ID 5-46]" → null (obviously)

    If you return a period, you MUST be able to cite the approximate year or century from memory.
  PROMPT

  def initialize(client: nil, model: nil)
    @client = client || LlmClient.new(model: model)
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
