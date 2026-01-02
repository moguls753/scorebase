# frozen_string_literal: true

# Infers musical period from score metadata using LLM.
#
# Usage:
#   inferrer = PeriodFromTitleInferrer.new(client: client)
#   results = inferrer.infer(scores)  # handles single or multiple
#
class PeriodFromTitleInferrer
  Result = Data.define(:period, :confidence, :error) do
    def success? = error.nil?
    def found? = period.present?
  end

  PERIODS = "Medieval (<1400), Renaissance (1400-1600), Baroque (1600-1750), " \
            "Classical (1750-1820), Romantic (1820-1900), Late Romantic (1880-1920), " \
            "Impressionist (1890-1920), 20th Century (1900-2000), Contemporary (2000+)"

  RULES = <<~RULES
    Return the period if you KNOW the composer. Return null if uncertain.

    IDENTIFY these (you know their dates):
    - Bach, Mozart, Beethoven, Handel, Haydn → Classical/Baroque
    - Chopin, Brahms, Tchaikovsky, Verdi → Romantic
    - Debussy, Ravel → Impressionist
    - Stravinsky, Shostakovich → 20th Century
    - Any composer whose birth/death years you know from training

    Return NULL for:
    - Composer is NA, Unknown, Traditional, Anonymous, Trad, or empty
    - You don't recognize the composer name
    - Hymn/folk title with unknown composer (don't guess Classical!)
  RULES

  SINGLE_PROMPT = <<~PROMPT
    Identify the musical period from sheet music metadata.

    Title: %{title}
    Composer: %{composer}
    Genre: %{genre}
    Description: %{description}

    Periods: #{PERIODS}

    JSON: {"period": "Baroque" or null, "confidence": "high/low"}

    #{RULES}
  PROMPT

  BATCH_PROMPT = <<~PROMPT
    Identify the musical period for each score below.

    %{scores_data}

    Periods: #{PERIODS}

    JSON: {"results": [{"id": 1, "period": "Baroque" or null, "confidence": "high/low"}, ...]}

    #{RULES}
  PROMPT

  def initialize(client:)
    @client = client
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
      period: response["period"],
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
      genre: score.genre.presence || "unknown",
      description: score.description.to_s.truncate(100)
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
    parts << "   Genre: #{score.genre}" if score.genre.present?
    parts << "   Description: #{score.description.to_s.truncate(100)}" if score.description.present?
    parts.join("\n")
  end

  def parse_batch_response(response, count)
    results = response["results"] || []

    Array.new(count) do |i|
      result = results[i] || {}
      Result.new(
        period: result["period"],
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

    Result.new(period: nil, confidence: nil, error: message)
  end
end
