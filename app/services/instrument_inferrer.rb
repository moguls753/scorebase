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
    Identify instruments from sheet music metadata.

    Title: %{title}
    Composer: %{composer}
    Period: %{period}
    Voicing: %{voicing}
    Parts: %{num_parts}

    JSON: {"instruments": "Piano", "confidence": "high/medium/low"}

    Rules:
    - Standard English names: Piano, Violin, Flute, Organ, Guitar, etc.
    - Comma-separated: "Violin, Viola, Cello" (not "String Trio")
    - Orchestra (15+ instruments): "Orchestra"
    - Vocal with accompaniment: "Vocal, Piano" or "Vocal, Orchestra"
    - A cappella: "Vocal"
    - Some composers mainly wrote for one instrument:
      Sor, Giuliani, Carulli, Tárrega, Barrios → Guitar
      Chopin, Liszt, Czerny → Piano
      Paganini → Violin
    - Return null if truly unknown
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
      num_parts: score.num_parts.to_i
    )
  end
end
