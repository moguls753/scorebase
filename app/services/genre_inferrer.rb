# frozen_string_literal: true

# Infers normalized genre from score metadata using LLM.
#
# Usage:
#   result = GenreInferrer.infer(score)
#   result.genre      # => "Motet" or nil
#   result.confidence # => "high", "medium", "low"
#   result.success?   # => true (API call succeeded, even if genre is nil)
#   result.found?     # => true (genre was identified)
#
class GenreInferrer
  VOCABULARY_PATH = Rails.root.join("config/genre_vocabulary.yml").freeze
  GENRES = YAML.load_file(VOCABULARY_PATH).fetch("genres").freeze

  Result = Data.define(:genre, :confidence, :error) do
    def success? = error.nil?       # API call succeeded (genre may be nil if not determinable)
    def found? = genre.present?     # Genre was identified
  end

  PROMPT = <<~PROMPT
    You classify sheet music into genres. Pick ONE genre from this list:
    %{genres}

    If none fit well, respond with null.

    Score metadata:
    - Title: %{title}
    - Composer: %{composer}
    - Existing tags: %{tags}
    - Voicing: %{voicing}
    - Instruments: %{instruments}

    Respond with JSON only:
    {"genre": "Genre Name", "confidence": "high|medium|low"}

    Use "high" when title explicitly contains the genre (e.g., "Requiem in D minor" → Requiem).
    Use "medium" when inferring from composer style or context.
    Use "low" when guessing.
  PROMPT

  def initialize(client: nil)
    @client = client || LlmClient.new
  end

  def infer(score)
    response = @client.chat_json(build_prompt(score))
    genre = response["genre"]

    # Validate against vocabulary
    unless genre.nil? || GENRES.include?(genre)
      Rails.logger.warn "[GenreInferrer] Unknown genre returned: #{genre}"
      genre = nil
    end

    Result.new(genre: genre, confidence: response["confidence"], error: nil)
  rescue JSON::ParserError => e
    Result.new(genre: nil, confidence: nil, error: "JSON parse error: #{e.message}")
  rescue LlmClient::Error => e
    Result.new(genre: nil, confidence: nil, error: e.message)
  rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout => e
    Result.new(genre: nil, confidence: nil, error: "Network timeout: #{e.message}")
  rescue StandardError => e
    Result.new(genre: nil, confidence: nil, error: "Unexpected error: #{e.class} - #{e.message}")
  end

  private

  def build_prompt(score)
    format(PROMPT,
      genres: GENRES.join(", "),
      title: score.title.to_s,
      composer: score.composer.to_s,
      tags: extract_tags(score),
      voicing: score.voicing.to_s.presence || "unknown",
      instruments: score.instruments.to_s.presence || "unknown"
    )
  end

  def extract_tags(score)
    tags = []
    tags.concat(score.genre_list) if score.genre.present? && score.genre != "NA"
    tags.concat(score.tag_list) if score.tags.present? && score.tags != "NA"
    tags.empty? ? "none" : tags.join(", ")
  end
end
