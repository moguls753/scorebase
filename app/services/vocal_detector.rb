# frozen_string_literal: true

# Detects whether a score is vocal music using LLM analysis of multiple signals.
# Fixes unreliable has_vocal field by reasoning about all available metadata.
#
# Usage:
#   detector = VocalDetector.new(client: client)
#   results = detector.detect(scores)  # handles single or multiple
#
class VocalDetector
  Result = Data.define(:has_vocal, :confidence, :error) do
    def success? = error.nil?
  end

  RULES = <<~RULES
    Determine if this score contains ANY vocal parts (singers/choir).
    Return true if there are ANY vocal parts, even if mixed with instruments.

    CRITICAL: Distinguish between vocal voice names and instrumental names!

    VOCAL PART INDICATORS (return true if found):
    - "Voice", "Vocal" - clear vocal indicators
    - "Soprano" UNLESS followed by "Saxophone" → "Soprano" alone = vocal, "Soprano Saxophone" = instrumental
    - "Alto" UNLESS followed by "Saxophone" or in orchestra with "Violin" → standalone "Alto" in SATB = vocal
    - "Tenor" UNLESS followed by "Saxophone" → "Tenor" alone = vocal, "Tenor Saxophone" = instrumental
    - "Bass" UNLESS followed by "Guitar", "Drum", "Clarinet" or preceded by "Electric"/"Acoustic" → SATB "Bass" = vocal
    - "Sopran", "Alt", "Bariton", "Mezzosopran" (German vocal names)
    - "Choir", "Chorus" with has_extracted_lyrics=true → vocal
    - Single letters: "S", "A", "T", "B" (likely SATB abbreviations) → vocal

    INSTRUMENTAL (NOT vocal):
    - "Alto Saxophone", "Alto Sax" → instrumental
    - "Tenor Saxophone", "Tenor Sax" → instrumental
    - "Soprano Saxophone" → instrumental
    - "Electric Bass", "Acoustic Bass", "Bass Guitar", "Bass Drum" → instrumental
    - "Altos" in orchestra (with "Violin", "Violons") → French for violas, instrumental
    - Pure instrumental: "Piano", "Guitar", "Trumpet", "Violin" without vocal parts

    DECISION PROCESS:
    1. Scan Part Names for vocal indicators
    2. BUT check if they're part of instrumental names (e.g., "Alto Saxophone")
    3. If has_extracted_lyrics=true → strong vocal indicator (unless all parts are instrumental)
    4. If unsure, check clefs (f+g together common for SATB)

    EXAMPLES:
    - "Voice, Piano, Guitar" → TRUE (has Voice)
    - "Alto Saxophone, Piano" → FALSE (Alto is part of "Alto Saxophone")
    - "Soprano, Alto, Tenor, Bass, Organ" → TRUE (SATB vocal parts)
    - "Violin, Altos, Cello" → FALSE ("Altos" = violas in orchestra)
    - "Voice, Alto Saxophone, Trumpet" → TRUE (has Voice, even with instruments)

    Return has_vocal as true/false with confidence (high/medium/low).
  RULES

  SINGLE_PROMPT = <<~PROMPT
    Determine if this is vocal or instrumental music.

    Title: %{title}
    Composer: %{composer}
    Part Names: %{part_names}
    Detected Instruments: %{detected_instruments}
    Has Extracted Lyrics: %{has_extracted_lyrics}
    Clefs Used: %{clefs_used}
    Pitch Ranges: %{pitch_ranges}

    JSON: {"has_vocal": true/false, "confidence": "high/medium/low"}

    #{RULES}
  PROMPT

  BATCH_PROMPT = <<~PROMPT
    Determine if each score below is vocal or instrumental music.

    %{scores_data}

    JSON: {"results": [{"id": 1, "has_vocal": true/false, "confidence": "high/medium/low"}, ...]}

    #{RULES}
  PROMPT

  def initialize(client: nil)
    @client = client || LlmClient.new(backend: :openai)
  end

  # Process one or many scores - always returns Array<Result>
  def detect(scores)
    scores = Array(scores)
    return [] if scores.empty?
    return [detect_single(scores.first)] if scores.one?

    detect_batch(scores)
  end

  private

  def detect_single(score)
    response = @client.chat_json(build_single_prompt(score))

    Result.new(
      has_vocal: response["has_vocal"],
      confidence: response["confidence"],
      error: nil
    )
  rescue => e
    error_result(e)
  end

  def detect_batch(scores)
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
      has_extracted_lyrics: score.has_extracted_lyrics || false,
      clefs_used: score.clefs_used.presence || "unknown",
      pitch_ranges: format_pitch_ranges(score.pitch_range_per_part)
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
    parts << "   Has Extracted Lyrics: #{score.has_extracted_lyrics || false}"
    parts << "   Clefs: #{score.clefs_used}" if score.clefs_used.present?

    if score.pitch_range_per_part.present?
      ranges = format_pitch_ranges(score.pitch_range_per_part)
      parts << "   Pitch Ranges: #{ranges}" if ranges != "unknown"
    end

    parts.join("\n")
  end

  def format_pitch_ranges(ranges)
    return "unknown" if ranges.blank?

    # Parse JSON if it's a string
    ranges = JSON.parse(ranges) if ranges.is_a?(String)

    # Format as: "Part: low-high, Part: low-high"
    ranges.map { |part, range| "#{part}: #{range['low']}-#{range['high']}" }.join(", ")
  rescue
    "unknown"
  end

  def parse_batch_response(response, count)
    results = response["results"] || []

    Array.new(count) do |i|
      result = results.find { |r| r["id"] == i + 1 } || results[i] || {}
      Result.new(
        has_vocal: result["has_vocal"],
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

    Result.new(has_vocal: nil, confidence: nil, error: message)
  end
end
