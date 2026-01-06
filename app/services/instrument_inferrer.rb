# frozen_string_literal: true

# Extracts instruments from INSTRUMENTAL scores using LLM.
# Only runs on has_vocal=false scores (vocal scores use VoicingNormalizer).
# Uses part_names/detected_instruments when available, falls back to metadata inference.
#
# Usage:
#   inferrer = InstrumentInferrer.new(client: client)
#   results = inferrer.infer(scores)  # handles single or multiple
#
class InstrumentInferrer
  Result = Data.define(:instruments, :confidence, :error) do
    def success? = error.nil?
    def found? = instruments.present?
  end

  RULES = <<~RULES
    Extract instruments from this INSTRUMENTAL score (confirmed no vocals).

    TRUSTED DATA (already normalized):
    - composer: normalized composer name
    - period: normalized period (Baroque, Classical, Romantic, Modern, etc.)

    RAW DATA (may contain garbage - use judgment):
    - part_names: raw MusicXML part names (may be garbage like "MusicXML Part", "Unnamed")
    - detected_instruments: extracted instruments (may have MIDI names like "Grand Piano")
    - title: raw title

    NORMALIZE:
    - Standard English names: Piano, Violin, Flute, Organ, Guitar, Cello, etc.
    - "Grand Piano" → Piano
    - "Violons" → Violin, "Altos" → Viola, "Violoncelle" → Cello, "Contrebasse" → Double Bass
    - "Acordeón" → Accordion
    - Filter garbage: "MusicXML Part", "Unnamed", "Staff", "SmartMusic SoftSynth", "Midi_XX"
    - Deduplicate: "Piano, Piano, Piano" → Piano

    FORMAT:
    - Comma-separated list: "Violin, Viola, Cello"
    - Large ensembles (15+ parts): "Orchestra"
    - Standard groups acceptable: "String Quartet", "Piano Trio"

    USE ALL SIGNALS:
    - If part_names has real instruments → use them
    - If part_names is garbage → use detected_instruments
    - If both garbage → infer from title ("Piano Sonata" → Piano)
    - Composer hints: Chopin/Liszt → Piano, Sor/Tárrega → Guitar, Paganini → Violin
    - Return null only if truly unknown from all signals
  RULES

  SINGLE_PROMPT = <<~PROMPT
    Extract instruments from this instrumental score.

    Title: %{title}
    Composer: %{composer}
    Period: %{period}
    Part Names: %{part_names}
    Detected Instruments: %{detected_instruments}
    Number of Parts: %{num_parts}

    JSON: {"instruments": "Piano", "confidence": "high/medium/low"}

    #{RULES}
  PROMPT

  BATCH_PROMPT = <<~PROMPT
    Extract instruments from each instrumental score below.

    %{scores_data}

    JSON: {"results": [{"id": 1, "instruments": "Piano", "confidence": "high/medium/low"}, ...]}

    #{RULES}
  PROMPT

  def initialize(client: nil)
    @client = client || LlmClient.new(backend: :openai)
  end

  # Process one or many scores - always returns Array<Result>
  def infer(scores)
    scores = Array(scores)
    return [] if scores.empty?
    return [infer_single(scores.first)] if scores.one?

    infer_batch(scores)
  end

  private

  def infer_single(score)
    response = @client.chat_json(build_single_prompt(score))

    Result.new(
      instruments: response["instruments"],
      confidence: response["confidence"],
      error: nil
    )
  rescue => e
    error_result(e)
  end

  def infer_batch(scores)
    response = @client.chat_json(build_batch_prompt(scores))
    parse_batch_response(response, scores.length)
  rescue => e
    Array.new(scores.length) { error_result(e) }
  end

  def build_single_prompt(score)
    format(SINGLE_PROMPT,
      title: score.title.to_s,
      composer: score.composer.to_s,
      period: score.period.presence || "unknown",
      part_names: score.part_names.presence || "unknown",
      detected_instruments: score.detected_instruments.presence || "unknown",
      num_parts: score.num_parts.to_i
    )
  end

  def build_batch_prompt(scores)
    scores_data = scores.each_with_index.map { |score, i|
      build_score_entry(score, i + 1)
    }.join("\n")

    format(BATCH_PROMPT, scores_data: scores_data)
  end

  def build_score_entry(score, index)
    parts = ["#{index}. Title: #{score.title}"]
    parts << "   Composer: #{score.composer}" if score.composer.present?
    parts << "   Period: #{score.period}" if score.period.present?
    parts << "   Part Names: #{score.part_names}" if score.part_names.present?
    parts << "   Detected Instruments: #{score.detected_instruments}" if score.detected_instruments.present?
    parts << "   Number of Parts: #{score.num_parts}" if score.num_parts.to_i > 0
    parts.join("\n")
  end

  def parse_batch_response(response, count)
    results = response["results"] || []

    Array.new(count) do |i|
      result = results.find { |r| r["id"] == i + 1 } || results[i] || {}
      Result.new(
        instruments: result["instruments"],
        confidence: result["confidence"],
        error: nil
      )
    end
  end

  def error_result(error)
    message = case error
    when JSON::ParserError then "JSON parse error"
    when LlmClient::Error then error.message
    when Timeout::Error, Net::OpenTimeout, Net::ReadTimeout then "Network timeout"
    else "#{error.class}: #{error.message}"
    end

    Result.new(instruments: nil, confidence: nil, error: message)
  end
end
