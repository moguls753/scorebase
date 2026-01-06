# frozen_string_literal: true

# Infers normalized genre from score metadata using LLM.
#
# Usage:
#   inferrer = GenreInferrer.new(client: client)
#   results = inferrer.infer(scores)  # handles single or multiple
#   results.first.genre      # => "Motet" or nil
#   results.first.confidence # => "high", "medium", "low"
#   results.first.success?   # => true (API call succeeded, even if genre is nil)
#   results.first.found?     # => true (genre was identified)
#
class GenreInferrer
  VOCABULARY_PATH = Rails.root.join("config/genre_vocabulary.yml").freeze
  GENRES = YAML.load_file(VOCABULARY_PATH).fetch("genres").freeze

  Result = Data.define(:genre, :confidence, :error) do
    def success? = error.nil?       # API call succeeded (genre may be nil if not determinable)
    def found? = genre.present?     # Genre was identified
  end

  RULES = <<~RULES
    TRUSTED DATA (already normalized, reliable):
    - composer: normalized composer name (may be "NA" if unknown)
    - period: Baroque, Classical, Romantic, Modern, Contemporary (may be "unknown")
    - has_vocal: yes/no/unknown
    - voicing: SATB, SSA, etc. (only for vocal works, otherwise "none")
    - instruments: Piano, Orchestra, etc. (may be "unknown")

    RAW DATA (may contain garbage):
    - title: original title (usually reliable)
    - tags: original metadata (often unreliable or missing)

    GENRES (pick ONE exactly as shown, or null): %{genres}

    INFERENCE STRATEGY:
    1. Title keywords are strongest: "Requiem", "Magnificat", "Sonata" in title → high confidence
    2. Combine period + has_vocal + instruments:
       - Baroque + vocal + SATB → Motet, Cantata, Mass
       - Romantic + Piano → Sonata, Prelude, Etude, Nocturne
       - Orchestra → Symphony, Concerto, Suite
    3. Composer hints (validate against period):
       - Bach → Chorale, Fugue, Cantata, Prelude
       - Palestrina/Victoria → Motet, Mass
       - Mozart/Beethoven → Sonata, Symphony, Concerto
       - Schubert/Schumann → Art Song (vocal) or Sonata (piano)
       - Chopin/Liszt → Etude, Nocturne, Waltz, Polonaise, Ballade

    VOCAL vs INSTRUMENTAL:
    - Vocal only: Mass, Requiem, Motet, Magnificat, Anthem, Hymn, Cantata, Oratorio, Madrigal, Chanson, Art Song, Opera, Folk Song, Carol, Spiritual, Gospel
    - Instrumental only: Sonata, Fugue, Prelude, Suite, Concerto, Symphony, Etude, Nocturne, Waltz, Minuet, March
    - Either: Chorale, Psalm, Traditional, Folk, Educational

    CONFIDENCE: high (title match), medium (multiple signals), low (single signal)

    IMPORTANT: Return genre exactly as shown in the list. Return null if no genre fits.
  RULES

  SINGLE_PROMPT = <<~PROMPT
    Classify this sheet music into a genre.

    TRUSTED:
    - Composer: %{composer}
    - Period: %{period}
    - Vocal: %{has_vocal}
    - Voicing: %{voicing}
    - Instruments: %{instruments}

    RAW:
    - Title: %{title}
    - Tags: %{tags}

    JSON: {"genre": "Genre Name", "confidence": "high|medium|low"}

    %{rules}
  PROMPT

  BATCH_PROMPT = <<~PROMPT
    Classify each sheet music score into a genre.

    %{scores_data}

    JSON: {"results": [{"id": 1, "genre": "Genre Name", "confidence": "high|medium|low"}, ...]}

    %{rules}
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
    build_result(response)
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
      composer: score.composer.presence || "unknown",
      period: score.period.presence || "unknown",
      has_vocal: format_has_vocal(score),
      voicing: score.voicing.presence || "none",
      instruments: score.instruments.presence || "unknown",
      tags: extract_tags(score),
      rules: format(RULES, genres: GENRES.join(", "))
    )
  end

  def build_batch_prompt(scores)
    scores_data = scores.each_with_index.map { |score, i|
      build_score_entry(score, i + 1)
    }.join("\n")

    format(BATCH_PROMPT,
      scores_data: scores_data,
      rules: format(RULES, genres: GENRES.join(", "))
    )
  end

  def build_score_entry(score, index)
    <<~ENTRY.strip
      #{index}. TRUSTED: Composer=#{score.composer.presence || 'unknown'} | Period=#{score.period.presence || 'unknown'} | Vocal=#{format_has_vocal(score)} | Voicing=#{score.voicing.presence || 'none'} | Instruments=#{score.instruments.presence || 'unknown'}
         RAW: Title=#{score.title} | Tags=#{extract_tags(score)}
    ENTRY
  end

  def format_has_vocal(score)
    case score.has_vocal
    when true then "yes"
    when false then "no"
    else "unknown"
    end
  end

  def extract_tags(score)
    tags = []
    tags.concat(score.genre_list) if score.genre.present? && score.genre != "NA"
    tags.concat(score.tag_list) if score.tags.present? && score.tags != "NA"
    tags.empty? ? "none" : tags.join(", ")
  end

  def build_result(response)
    return Result.new(genre: nil, confidence: nil, error: "Invalid response format") unless response.is_a?(Hash)

    genre = response["genre"]

    # Validate against vocabulary
    unless genre.nil? || GENRES.include?(genre)
      Rails.logger.warn "[GenreInferrer] Unknown genre returned: #{genre}"
      genre = nil
    end

    Result.new(genre: genre, confidence: response["confidence"], error: nil)
  end

  def parse_batch_response(response, count)
    results = response["results"] || []

    Array.new(count) do |i|
      result = results.find { |r| r["id"] == i + 1 } || results[i] || {}
      build_result(result)
    end
  end

  def error_result(error)
    message = case error
    when JSON::ParserError then "JSON parse error"
    when LlmClient::Error then error.message
    when Timeout::Error, Net::OpenTimeout, Net::ReadTimeout then "Network timeout"
    else "#{error.class}: #{error.message}"
    end

    Result.new(genre: nil, confidence: nil, error: message)
  end
end
