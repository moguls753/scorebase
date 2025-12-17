# frozen_string_literal: true

class GroqComposerNormalizer < ComposerNormalizerBase
  API_ENDPOINT = "https://api.groq.com/openai/v1/chat/completions"
  # 8B model: ~$0.05/1M input, $0.08/1M output (~$0.21 total for 27k composers)
  # 70B model: ~$0.59/1M input, $0.79/1M output (~$2.23 total)
  MODEL = ENV.fetch("GROQ_MODEL", "llama-3.1-8b-instant")
  MAX_RETRIES = 3
  RETRY_DELAY = 2

  class JsonParseError < StandardError; end

  def initialize(limit: nil)
    super
    @api_key = ENV["GROQ_API_KEY"]
    raise "GROQ_API_KEY environment variable not set" if @api_key.nil?
  end

  def provider_name
    "groq"
  end

  private

  def request_batch(batch)
    scores_data = batch.each_with_index.map do |(composer, title, editor, genres, language), idx|
      { index: idx, composer: composer, title: title, editor: editor, genres: genres, language: language }
    end

    retries = 0
    begin
      response = send_http_request(
        URI(API_ENDPOINT),
        build_payload(scores_data),
        { "Authorization" => "Bearer #{@api_key}" }
      )
      parse_response(response)
    rescue JsonParseError => e
      retries += 1
      if retries <= MAX_RETRIES
        puts "  Retry #{retries}/#{MAX_RETRIES} after JSON parse error..."
        sleep RETRY_DELAY
        retry
      else
        puts "  Failed after #{MAX_RETRIES} retries: #{e.message}"
        nil
      end
    end
  end

  def build_payload(scores_data)
    {
      model: MODEL,
      temperature: 0.1,
      response_format: { type: "json_object" },
      messages: [{ role: "user", content: build_prompt(scores_data) }]
    }
  end

  def parse_response(response)
    raise QuotaExceededError if response.code == "429"

    unless response.code == "200"
      puts "  API Error #{response.code}: #{response.body[0..200]}"
      return nil
    end

    body = JSON.parse(response.body)
    text = body.dig("choices", 0, "message", "content")

    unless text
      puts "  No text in response: #{body.keys}"
      return nil
    end

    # Strip markdown code fences if present
    text = text.gsub(/\A```(?:json)?\s*/, "").gsub(/\s*```\z/, "").strip

    parsed = JSON.parse(text)
    parsed.is_a?(Array) ? parsed : parsed.values.first
  rescue QuotaExceededError
    raise # Re-raise to trigger provider switch
  rescue JSON::ParserError => e
    puts "  JSON parse error: #{e.message}"
    raise JsonParseError, e.message
  rescue => e
    puts "  Error: #{e.class} - #{e.message}"
    nil
  end
end
