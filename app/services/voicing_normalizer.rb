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
    Extract voicing and complete instrumentation from this VOCAL score.
    The score has been confirmed to contain vocal parts (has_vocal=true).

    TRUSTED DATA (already normalized):
    - composer: normalized composer name
    - period: normalized period (Baroque, Classical, Romantic, Modern, etc.)
    - has_vocal: confirmed true

    RAW DATA (may contain garbage - use judgment):
    - part_names: raw MusicXML part names (may have MIDI garbage)
    - detected_instruments: extracted instruments (may have MIDI names)
    - title: raw title

    VOICING EXTRACTION:
    - Output ONLY voice part codes: SATB, SAB, SSA, SSAA, TTBB, SSAATTBB, TB, SA, Solo S, Solo T, etc.
    - NEVER output "a cappella" as voicing - that describes accompaniment, not voice parts
    - S = Soprano, A = Alto, T = Tenor, B = Bass/Baritone
    - Count repeated letters for divisi: "Soprano 1, Soprano 2, Alto" → SSA
    - Recognize voice indicators:
      - "Soprano Voice", "Tenor Voice", "Baritone Voice" → S, T, B
      - "Voice" alone → Solo (use num_parts to determine)
    - Map non-English names:
      - German: Sopran→S, Alt→A, Tenor→T, Bass/Bariton→B
      - Italian: Canto/Cantus→S, Alto/Altus→A, Tenore→T, Basso/Bassus→B, Quinto→A or T (context)
      - Latin: Superius/Discantus→S, Contratenor→A
      - Catalan: Soprà→S, Baixos→B, Tenors→T, Alts→A
    - "Men" or "Male voices" → TB or TTBB
    - "Women" or "Female voices" → SA or SSA
    - Solo voice: use "Solo S", "Solo T", etc.
    - If voice parts unclear from part_names, use num_parts as hint (4 parts → SATB)
    - IGNORE garbage: "MusicXML Part", "Staff", "Unnamed", "Practice"

    INSTRUMENTS EXTRACTION (complete instrumentation):
    - List ALL performing forces: voices FIRST, then accompaniment
    - Use the voicing code for voices, then add accompaniment instruments
    - Format: "SATB, Piano" or "Solo S, Orchestra" or "SSA" (if no accompaniment)
    - Common accompaniment: Piano, Organ, Orchestra, Guitar, Harp, Basso Continuo
    - Recognize markers:
      - "Accomp.", "Acc.", "Accompaniment" → Piano (or Organ if church context)
      - "BC", "B.C.", "Basso Continuo", "Continuo" → Basso Continuo
    - Normalize MIDI garbage: "Grand Piano" → Piano, "SmartMusic SoftSynth" → ignore
    - If NO accompaniment found, instruments = just the voicing code (e.g., "SATB")

    EXAMPLES:
    - part_names="Soprano, Alto, Tenor, Bass, Piano" → voicing="SATB", instruments="SATB, Piano"
    - part_names="Sopran, Alt, Tenor, Bass" → voicing="SATB", instruments="SATB"
    - part_names="Canto, Alto, Tenore, Basso, Orgue" → voicing="SATB", instruments="SATB, Organ"
    - part_names="Soprano 1, Soprano 2, Alto" → voicing="SSA", instruments="SSA"
    - part_names="Choir Aahs, Grand Piano" num_parts=4 → voicing="SATB", instruments="SATB, Piano"
    - part_names="TENOR LEAD, BARI BASS" → voicing="TB", instruments="TB"
    - part_names="Voice Oohs" num_parts=4 → voicing="SATB", instruments="SATB"
    - part_names="Soprano, Alto, Tenor, Bass, Organ" → voicing="SATB", instruments="SATB, Organ"
    - part_names="Soprano Voice, Tenor Voice, Baritone Voice" → voicing="STB", instruments="STB"
    - part_names="Canto, BC, BC" → voicing="Solo S", instruments="Solo S, Basso Continuo"
    - part_names="Solo, Piano, Violin" → voicing="Solo S", instruments="Solo S, Piano, Violin"

    Return voicing (voice codes only), instruments (voices + accompaniment), confidence (high/medium/low).
  RULES

  SINGLE_PROMPT = <<~PROMPT
    Extract voicing and complete instrumentation from this vocal score.

    Title: %{title}
    Composer: %{composer}
    Period: %{period}
    Part Names: %{part_names}
    Detected Instruments: %{detected_instruments}
    Number of Parts: %{num_parts}

    JSON: {"voicing": "SATB", "instruments": "SATB, Piano", "confidence": "high/medium/low"}

    #{RULES}
  PROMPT

  BATCH_PROMPT = <<~PROMPT
    Extract voicing and complete instrumentation from each vocal score below.

    %{scores_data}

    JSON: {"results": [{"id": 1, "voicing": "SATB", "instruments": "SATB, Piano", "confidence": "high/medium/low"}, ...]}

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
