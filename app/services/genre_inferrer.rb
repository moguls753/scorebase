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
    Rules:
    - Pick ONE genre from this list: %{genres}
    - If none fit well, respond with null
    - Use "high" when title explicitly contains the genre (e.g., "Requiem in D minor" → Requiem)
    - Use "medium" when inferring from composer style or context
    - Use "low" when guessing
  RULES

  SINGLE_PROMPT = <<~PROMPT
    Classify this sheet music into a genre.

    Title: %{title}
    Composer: %{composer}
    Existing tags: %{tags}
    Voicing: %{voicing}
    Instruments: %{instruments}

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
      composer: score.composer.to_s,
      tags: extract_tags(score),
      voicing: score.voicing.to_s.presence || "unknown",
      instruments: score.instruments.to_s.presence || "unknown",
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
    parts = ["#{index}. Title: #{score.title}"]
    parts << "   Composer: #{score.composer}" if score.composer.present?
    parts << "   Tags: #{extract_tags(score)}"
    parts << "   Voicing: #{score.voicing}" if score.voicing.present?
    parts << "   Instruments: #{score.instruments}" if score.instruments.present?
    parts.join("\n")
  end

  def extract_tags(score)
    tags = []
    tags.concat(score.genre_list) if score.genre.present? && score.genre != "NA"
    tags.concat(score.tag_list) if score.tags.present? && score.tags != "NA"
    tags.empty? ? "none" : tags.join(", ")
  end

  def build_result(response)
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
