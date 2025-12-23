# frozen_string_literal: true

# Infers instruments from score metadata using LLM.
#
# Usage:
#   result = InstrumentInferrer.new.infer(score)
#   result.instruments  # => "Piano" or "Violin, Viola, Cello" or nil
#   result.success?     # => true (API call succeeded)
#   result.found?       # => true (instruments were identified)
#
class InstrumentInferrer
  Result = Data.define(:instruments, :confidence, :error) do
    def success? = error.nil?
    def found? = instruments.present?
  end

  PROMPT = <<~PROMPT
    You identify musical instruments from sheet music metadata.

    Score metadata:
    - Title: %{title}
    - Composer: %{composer}
    - Period: %{period}
    - Voicing: %{voicing}
    - Number of parts: %{num_parts}
    - Detected (hint, may be wrong): %{detected}

    What instrument(s) is this piece for?

    Respond with JSON only:
    {"instruments": "Piano", "confidence": "high"}

    Rules:
    - Use standard English names: Piano, Violin, Flute, Organ, Guitar, etc.
    - List instruments comma-separated: "Violin, Viola, Cello" (not "String Trio")
    - For full symphony orchestra (15+ instruments): "Orchestra"
    - For vocal music: include "Vocal" plus any accompaniment ("Vocal, Piano" or "Vocal, Orchestra")
    - For a cappella (voices only): just "Vocal"
    - Confidence: "high" if explicit in title, "medium" if inferred, "low" if guessing
  PROMPT

  def initialize(client: nil)
    @client = client || LlmClient.new
  end

  def infer(score)
    response = @client.chat_json(build_prompt(score))

    Result.new(
      instruments: response["instruments"],
      confidence: response["confidence"],
      error: nil
    )
  rescue JSON::ParserError => e
    Result.new(instruments: nil, confidence: nil, error: "JSON parse error: #{e.message}")
  rescue LlmClient::Error => e
    Result.new(instruments: nil, confidence: nil, error: e.message)
  rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout => e
    Result.new(instruments: nil, confidence: nil, error: "Network timeout: #{e.message}")
  rescue StandardError => e
    Result.new(instruments: nil, confidence: nil, error: "Unexpected error: #{e.class} - #{e.message}")
  end

  private

  def build_prompt(score)
    format(PROMPT,
      title: score.title.to_s,
      composer: score.composer.to_s,
      period: score.period.presence || "unknown",
      voicing: score.voicing.presence || "unknown",
      num_parts: score.num_parts.to_i,
      detected: score.detected_instruments.presence || "none"
    )
  end
end
