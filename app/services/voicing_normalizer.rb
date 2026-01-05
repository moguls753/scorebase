# frozen_string_literal: true

# Extracts voicing and instruments from vocal scores.
# Only runs on scores where has_vocal=true (confirmed by VocalDetector).
#
# Usage:
#   normalizer = VoicingNormalizer.new(client: client)
#   results = normalizer.normalize(scores)  # handles single or multiple
#
class VoicingNormalizer
  Result = Data.define(:voicing, :instruments, :confidence, :error) do
    def success? = error.nil?
    def found? = voicing.present?
  end

  RULES = <<~RULES
    Extract the voicing and accompaniment instruments from this VOCAL score.
    The score has already been confirmed to contain vocal parts.

    VOICING EXTRACTION:
    - Standard voicing codes: SATB, SAB, SSA, SSAA, TTBB, SSAATTBB, TB, SA, etc.
    - S = Soprano, A = Alto, T = Tenor, B = Bass/Baritone
    - Count repeated letters for divisi: "Soprano 1, Soprano 2, Alto" → SSA
    - Recognize voice indicators with suffixes:
      - "Soprano Voice", "Tenor Voice", "Baritone Voice" → S, T, B
      - "Voice" alone → Solo (use num_parts to determine)
    - Map non-English names:
      - German: Sopran→S, Alt→A, Tenor→T, Bass/Bariton→B
      - Italian: Canto/Cantus→S, Alto/Altus→A, Tenore→T, Basso/Bassus→B, Quinto→A or T (context)
      - Latin: Superius/Discantus→S, Contratenor→A
      - Catalan: Soprà→S, Baixos→B, Tenors→T, Alts→A
    - "Men" or "Male voices" → likely TB or TTBB
    - "Women" or "Female voices" → likely SA or SSA
    - Solo voice: use "Solo S", "Solo T", etc.
    - If voice parts are unclear from part_names, use num_parts as hint
    - IGNORE non-voice parts: "MusicXML Part", "Staff", "Unnamed", "Practice"

    INSTRUMENTS EXTRACTION (accompaniment only):
    - List ONLY the accompaniment instruments, NOT the voices
    - Common: Piano, Organ, Orchestra, Guitar, Harp
    - Recognize accompaniment markers:
      - "Accomp.", "Acc.", "Accompaniment" → Piano (or Organ if context suggests)
      - "BC", "B.C.", "Basso Continuo", "Continuo" → Basso Continuo
      - "Organ", "Orgue", "Church Organ", "Pipe Organ" → Organ
    - If no accompaniment instruments found → "a cappella"
    - Filter out MIDI garbage: "SmartMusic SoftSynth", "Choir Aahs", "Voice Oohs",
      "Midi_XX", "Sampler", "Grand Piano" → just "Piano", "Choir Pad" → ignore
    - Filter out voice names from instruments (they go in voicing)

    EXAMPLES:
    - part_names="Soprano, Alto, Tenor, Bass, Piano, Piano" → voicing="SATB", instruments="Piano"
    - part_names="Sopran, Alt, Tenor, Bass" → voicing="SATB", instruments="a cappella"
    - part_names="Canto, Alto, Tenore, Basso, Orgue" → voicing="SATB", instruments="Organ"
    - part_names="Soprano 1, Soprano 2, Alto" → voicing="SSA", instruments="a cappella"
    - part_names="Choir Aahs, Unnamed-000, Grand Piano" → voicing from num_parts, instruments="Piano"
    - part_names="TENOR LEAD, BARI BASS" → voicing="TB", instruments="a cappella"
    - part_names="Voice Oohs" with num_parts=4 → voicing="SATB" (infer), instruments="a cappella"
    - part_names="Soprano, Alto, Tenor, Bass, Accomp., Accomp." → voicing="SATB", instruments="Piano"
    - part_names="Soprano, Alto, Tenor, Bass, Acc., Acc." → voicing="SATB", instruments="Piano"
    - part_names="Soprano, Alto, Tenor, Bass, Organ, Organ" → voicing="SATB", instruments="Organ"
    - part_names="Soprano Voice, Tenor Voice, Baritone Voice" → voicing="STB", instruments="a cappella"
    - part_names="Canto, BC, BC" → voicing="Solo S", instruments="Basso Continuo"

    Return voicing (uppercase letters), instruments (proper names), confidence (high/medium/low).
  RULES

  SINGLE_PROMPT = <<~PROMPT
    Extract voicing and accompaniment from this vocal score.

    Title: %{title}
    Composer: %{composer}
    Part Names: %{part_names}
    Detected Instruments: %{detected_instruments}
    Number of Parts: %{num_parts}

    JSON: {"voicing": "SATB", "instruments": "Piano", "confidence": "high/medium/low"}

    #{RULES}
  PROMPT

  BATCH_PROMPT = <<~PROMPT
    Extract voicing and accompaniment from each vocal score below.

    %{scores_data}

    JSON: {"results": [{"id": 1, "voicing": "SATB", "instruments": "Piano", "confidence": "high/medium/low"}, ...]}

    #{RULES}
  PROMPT

  def initialize(client: nil)
    @client = client || LlmClient.new(backend: :openai)
  end

  # Process one or many scores - always returns Array<Result>
  def normalize(scores)
    scores = Array(scores)
    return [] if scores.empty?
    return [normalize_single(scores.first)] if scores.one?

    normalize_batch(scores)
  end

  private

  def normalize_single(score)
    response = @client.chat_json(build_single_prompt(score))

    Result.new(
      voicing: response["voicing"],
      instruments: response["instruments"],
      confidence: response["confidence"],
      error: nil
    )
  rescue => e
    error_result(e)
  end

  def normalize_batch(scores)
    response = @client.chat_json(build_batch_prompt(scores))
    parse_batch_response(response, scores.length)
  rescue => e
    Array.new(scores.length) { error_result(e) }
  end

  def build_single_prompt(score)
    format(SINGLE_PROMPT,
      title: score.title.to_s,
      composer: score.composer.to_s,
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
        voicing: result["voicing"],
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

    Result.new(voicing: nil, instruments: nil, confidence: nil, error: message)
  end
end
