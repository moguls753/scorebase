# frozen_string_literal: true

class GeminiComposerNormalizer < ComposerNormalizerBase
  API_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-lite:generateContent"
  MAX_RETRIES = 3
  RETRY_DELAY = 2

  class JsonParseError < StandardError; end

  def initialize(limit: nil)
    super
    @api_key = ENV["GEMINI_API_KEY"]
    raise "GEMINI_API_KEY environment variable not set" if @api_key.nil?
  end

  def provider_name
    "gemini"
  end

  private

  def request_batch(batch)
    scores_data = batch.each_with_index.map do |(composer, title, editor, genres, language), idx|
      { index: idx, composer: composer, title: title, editor: editor, genres: genres, language: language }
    end

    retries = 0
    begin
      response = send_http_request(
        URI("#{API_ENDPOINT}?key=#{@api_key}"),
        build_payload(scores_data)
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
      contents: [{ parts: [{ text: build_prompt(scores_data) }] }],
      generationConfig: { responseMimeType: "application/json", temperature: 0.1 }
    }
  end

  def parse_response(response)
    raise QuotaExceededError if response.code == "429"

    unless response.code == "200"
      puts "  API Error #{response.code}: #{response.body[0..200]}"
      return nil
    end

    body = JSON.parse(response.body)
    text = body.dig("candidates", 0, "content", "parts", 0, "text")

    unless text
      puts "  No text in response: #{body.keys}"
      return nil
    end

    # Strip markdown code fences if present (just in case)
    text = text.gsub(/\A```(?:json)?\s*/, "").gsub(/\s*```\z/, "").strip

    JSON.parse(text)
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
