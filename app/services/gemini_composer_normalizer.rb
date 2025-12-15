# frozen_string_literal: true

class GeminiComposerNormalizer < ComposerNormalizerBase
  API_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-lite:generateContent"

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
    scores_data = batch.map do |composer, title, editor, genres, language|
      { composer: composer, title: title, editor: editor, genres: genres, language: language }
    end

    response = send_http_request(
      URI("#{API_ENDPOINT}?key=#{@api_key}"),
      build_payload(scores_data)
    )
    parse_response(response)
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

    JSON.parse(text)
  rescue JSON::ParserError => e
    puts "  JSON parse error: #{e.message}"
    nil
  rescue => e
    puts "  Error: #{e.class} - #{e.message}"
    nil
  end
end
