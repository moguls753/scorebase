# frozen_string_literal: true

require "net/http"
require "json"
require "base64"
require "uri"

# SMD has no MusicXML, so music21 cannot run. This service fills the
# music21-shape columns from the page-1 preview image via Gemini vision.
# Marker: `extraction_status: :vision_extracted`. Idempotent.
class SmdVisionExtractor
  class Error < StandardError; end
  class RateLimitError < Error; end
  class ApiError < Error; end

  VERSION = "vision-gemini-2.5-flash-v1"
  MODEL = "gemini-2.5-flash"
  API_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/#{MODEL}:generateContent"

  Result = Struct.new(:status, :score, :error, :data, keyword_init: true)

  PROMPT = <<~PROMPT
    You are reading the first page of a sheet music PDF (rendered as image).
    Extract ONLY what is clearly visible. Never invent. Return null for any
    field you cannot read with confidence.

    Distinctions:
    - first_lyrics_line: actual sung words BELOW a staff (often hyphenated like
      "A-may-zing grace"). NOT the title, section header, medley name, or
      arrangement card. If you see only title text, return null.
    - key_signature: read from the staff (sharps/flats AFTER the clef). Format
      as "G major" or "F minor". If unclear or no staff, return null.
    - lyrics_language: ISO 639-1 two-letter code ("en", "de", "it", "fr",
      "es", "la"). null if no lyrics or unsure.

    Return strict JSON:
    {
      "is_music_score": true|false,
      "tempo_marking": "..." | null,
      "time_signature": "4/4" | null,
      "key_signature": "G major" | null,
      "voice_or_instrument_labels": [...] | [],
      "first_lyrics_line": "..." | null,
      "lyrics_language": "en"|"de"|... | null,
      "dedication_or_subtitle": "..." | null,
      "arranger": "..." | null
    }
  PROMPT

  def self.already_processed?(score)
    score.extraction_vision_extracted?
  end

  def initialize(score)
    @score = score
  end

  def call
    return skipped("already processed") if self.class.already_processed?(@score)
    return skipped("no preview_image_url") if @score.preview_image_url.blank?

    data = fetch_extraction
    apply(data)
    Result.new(status: :ok, score: @score, data: data)
  rescue RateLimitError => e
    Result.new(status: :rate_limited, score: @score, error: e.message)
  rescue Error => e
    Result.new(status: :failed, score: @score, error: e.message)
  end

  private

  def skipped(reason)
    Result.new(status: :skipped, score: @score, error: reason)
  end

  def fetch_extraction
    image_bytes = Net::HTTP.get(URI(@score.preview_image_url))
    raise ApiError, "empty image body" if image_bytes.blank?

    mime = @score.preview_image_url.match?(/\.jpe?g$/i) ? "image/jpeg" : "image/png"
    body = {
      contents: [{
        parts: [
          { text: PROMPT },
          { inline_data: { mime_type: mime, data: Base64.strict_encode64(image_bytes) } }
        ]
      }],
      generationConfig: { response_mime_type: "application/json", temperature: 0 }
    }

    uri = URI("#{API_ENDPOINT}?key=#{api_key}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 60

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req.body = body.to_json

    res = http.request(req)

    case res.code.to_i
    when 200
      payload = JSON.parse(res.body)
      raise ApiError, "Gemini error: #{payload.dig("error", "message")}" if payload["error"]
      JSON.parse(payload.dig("candidates", 0, "content", "parts", 0, "text"))
    when 429
      raise RateLimitError, "Gemini rate limited"
    else
      raise ApiError, "Gemini HTTP #{res.code}: #{res.body.to_s[0..200]}"
    end
  rescue JSON::ParserError => e
    raise ApiError, "JSON parse: #{e.message[0..150]}"
  end

  def api_key
    Rails.application.credentials.dig(:gemini, :api_key) || raise(ApiError, "gemini api key not configured")
  end

  def apply(data)
    marker = { extraction_status: :vision_extracted, extracted_at: Time.current }
    return @score.update!(marker) unless data["is_music_score"]

    updates = marker.dup

    if (raw_tempo = data["tempo_marking"]).present?
      updates[:tempo_marking] = raw_tempo.to_s.downcase.strip
      bpm = extract_bpm(raw_tempo)
      updates[:tempo_bpm] = bpm if bpm
    end

    updates[:time_signature] = data["time_signature"].to_s.strip if data["time_signature"].present?
    updates[:key_signature] = normalize_key(data["key_signature"]) if data["key_signature"].present?

    labels = Array(data["voice_or_instrument_labels"]).map { |l| l.to_s.strip }.reject(&:empty?)
    updates[:part_names] = labels.join(", ") if labels.any?

    if data["first_lyrics_line"].present?
      updates[:has_extracted_lyrics] = true
      updates[:lyrics_language] = data["lyrics_language"].to_s.downcase if data["lyrics_language"].present?
    end

    updates[:has_vocal] = derive_has_vocal(data, labels)

    @score.update!(updates)
  end

  # Match music21 format: "B-flat major" → "B- major", "C-sharp minor" → "C# minor"
  # Also handle unicode flat/sharp glyphs.
  def normalize_key(text)
    s = text.to_s.strip.gsub("♭", "-").gsub("♯", "#")
    s = s.sub(/^([A-G])[-\s]?flat\b/i) { "#{Regexp.last_match(1)}-" }
    s = s.sub(/^([A-G])[-\s]?sharp\b/i) { "#{Regexp.last_match(1)}#" }
    s
  end

  # Parse integer BPM from tempo strings like "♩ = 120", "J=78", "ca. 96", "= 124"
  def extract_bpm(text)
    match = text.to_s.match(/[♩♪♫j]?\s*=\s*(?:ca\.?\s*)?(\d{2,3})/i)
    match && match[1].to_i
  end

  VOCAL_LABEL_RE = /\b(soprano|alto|tenor|bass|baritone|countertenor|mezzo|voice|vocal|choir|chorus)\b/i

  def derive_has_vocal(data, labels)
    return true if data["first_lyrics_line"].present?
    labels.any? { |l| l.match?(VOCAL_LABEL_RE) }
  end
end
