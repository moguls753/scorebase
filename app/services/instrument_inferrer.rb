# frozen_string_literal: true

# Infers instruments from score metadata using LLM.
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
    Rules:
    - ONLY infer instruments explicitly indicated in metadata. DO NOT GUESS.
    - If voicing is empty/unknown and no instrument is mentioned in title: return null
    - Standard English names: Piano, Violin, Flute, Organ, Guitar, etc.
    - Comma-separated: "Violin, Viola, Cello" (not "String Trio")
    - Orchestra (15+ instruments): "Orchestra"
    - Vocal with accompaniment: "Vocal, Piano" or "Vocal, Orchestra"
    - A cappella or SATB/SSA/TTBB voicing without accompaniment: "Vocal"
    - Some composers mainly wrote for one instrument:
      Sor, Giuliani, Carulli, Tárrega, Barrios → Guitar
      Chopin, Liszt, Czerny → Piano
      Paganini → Violin
    - Return null if truly unknown (prefer null over guessing)
  RULES

  SINGLE_PROMPT = <<~PROMPT
    Identify instruments from sheet music metadata.

    Title: %{title}
    Composer: %{composer}
    Period: %{period}
    Voicing: %{voicing}
    Parts: %{num_parts}

    JSON: {"instruments": "Piano", "confidence": "high/medium/low"}

    #{RULES}
  PROMPT

  BATCH_PROMPT = <<~PROMPT
    Identify instruments for each score below.

    %{scores_data}

    JSON: {"results": [{"id": 1, "instruments": "Piano", "confidence": "high/medium/low"}, ...]}

    #{RULES}
  PROMPT

  def initialize(client: nil)
    @client = client || LlmClient.new
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
      voicing: score.voicing.presence || "unknown",
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
    parts << "   Voicing: #{score.voicing}" if score.voicing.present?
    parts << "   Parts: #{score.num_parts}" if score.num_parts.to_i > 0
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
