# frozen_string_literal: true

require "net/http"
require "json"

class GeminiComposerNormalizer
  BATCH_SIZE = 100
  BATCH_DELAY = 4 # seconds between batches

  # Gemini API
  # API_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"

  # Claude API
  API_ENDPOINT = "https://api.anthropic.com/v1/messages"
  ANTHROPIC_VERSION = "2023-06-01"
  MODEL = "claude-3-5-haiku-20241022" # Fast and cheap

  class QuotaExceededError < StandardError; end

  def initialize(api_key:, limit: nil)
    @api_key = api_key
    @limit = limit
    @mappings = AppSetting.get("composer_cache") || {}
  end

  def normalize!
    scores = fetch_scores
    puts "#{scores.count} unique composer fields to normalize#{@limit ? " (limited)" : ""}\n\n"
    puts "Resuming with #{@mappings.count} existing mappings\n" if @mappings.any?

    remaining = scores.reject { |row| @mappings.key?(row[0]) }
    puts "Remaining: #{remaining.count} composers\n\n"

    process_batches(remaining)
    print_summary
  end

  private

  def fetch_scores
    scores = Score.distinct
                  .pluck(:composer, :title, :editor, :genres, :language)
                  .uniq { |row| row[0] }

    @limit&.positive? ? scores.first(@limit) : scores
  end

  def process_batches(remaining)
    total_batches = (remaining.count / BATCH_SIZE.to_f).ceil

    remaining.each_slice(BATCH_SIZE).with_index do |batch, idx|
      puts "Batch #{idx + 1}/#{total_batches}"

      begin
        result = gemini_request(batch)
        apply_results(result)
        save_progress
      rescue QuotaExceededError
        puts "\n⚠️  Quota exceeded! Progress saved. Run again tomorrow."
        break
      end

      sleep BATCH_DELAY unless idx == total_batches - 1
    end
  end

  def apply_results(results)
    results&.each do |item|
      original = item["original"]
      normalized = item["normalized"]
      @mappings[original] = normalized

      if normalized
        updated = Score.where(composer: original).update_all(composer: normalized)
        puts "  [#{updated}] #{original[0..30].ljust(33)} -> #{normalized}"
      else
        puts "       #{original[0..30].ljust(33)} -> (unknown)"
      end
    end
  end

  def save_progress
    AppSetting.set("composer_cache", @mappings)
  end

  def print_summary
    puts "\n#{"=" * 50}"
    puts "Total processed: #{@mappings.count}"
    puts "Normalized & applied: #{@mappings.count { |_, v| v }}"
    puts "Unknown (unchanged): #{@mappings.count { |_, v| v.nil? }}"
    puts "\nProgress saved to database (app_settings.composer_cache)"
    puts "Run again to continue if quota was exceeded."
  end

  def gemini_request(batch)
    # Gemini
    # uri = URI("#{API_ENDPOINT}?key=#{@api_key}")

    # Claude
    uri = URI(API_ENDPOINT)

    scores_data = batch.map do |composer, title, editor, genres, language|
      { composer: composer, title: title, editor: editor, genres: genres, language: language }
    end

    response = send_request(uri, build_payload(scores_data))
    parse_response(response)
  end

  def build_payload(scores_data)
    prompt = <<~PROMPT
      Identify the COMPOSER for each music score. Return normalized as "LastName, FirstName".

      Use ALL fields to identify the composer:
      - composer field may contain the composer, arranger, piece title, or garbage
      - title often contains composer name (e.g., "Sonata by Mozart")
      - editor might be the arranger (original composer may be famous)
      - genres/language can hint at likely composers

      Rules:
      - Use the composer's ORIGINAL native language name, not anglicized versions
      - German composer -> German name: "Händel, Georg Friedrich" (not "Handel, George Frideric")
      - "J.S. Bach" -> "Bach, Johann Sebastian"
      - "Mozart" -> "Mozart, Wolfgang Amadeus"
      - "Handel" -> "Händel, Georg Friedrich"
      - "Tchaikovsky" -> "Чайковский, Пётр Ильич" or "Tschaikowski, Pjotr Iljitsch" (use Latin script)
      - If composer field is garbage but title hints at composer -> extract it
      - Traditional/folk music with no known composer -> null
      - If truly unknown -> null

      Input: #{scores_data.to_json}

      Return JSON: [{"original": "composer field value", "normalized": "LastName, FirstName" or null}]
    PROMPT

    # Gemini format
    # {
    #   contents: [{ parts: [{ text: prompt }] }],
    #   generationConfig: { responseMimeType: "application/json", temperature: 0.1 }
    # }

    # Claude format
    {
      model: MODEL,
      max_tokens: 4096,
      temperature: 0.1,
      messages: [
        { role: "user", content: prompt }
      ]
    }
  end

  def send_request(uri, payload)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.read_timeout = 60
    http.verify_callback = ->(_ok, _ctx) { true }

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"

    # Gemini auth
    # API key passed in URL

    # Claude auth
    req["x-api-key"] = @api_key
    req["anthropic-version"] = ANTHROPIC_VERSION

    req.body = payload.to_json

    http.request(req)
  end

  def parse_response(response)
    raise QuotaExceededError if response.code == "429"

    unless response.code == "200"
      puts "  API Error #{response.code}: #{response.body[0..200]}"
      return nil
    end

    body = JSON.parse(response.body)

    # Gemini format
    # text = body.dig("candidates", 0, "content", "parts", 0, "text")

    # Claude format
    text = body.dig("content", 0, "text")

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
