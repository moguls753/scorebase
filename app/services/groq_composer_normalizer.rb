# frozen_string_literal: true

require "net/http"
require "json"

class GroqComposerNormalizer
  BATCH_SIZE = 100
  BATCH_DELAY = 4 # seconds between batches
  API_ENDPOINT = "https://api.groq.com/openai/v1/chat/completions"
  MODEL = "llama-3.3-70b-versatile" # Good reasoning, fast

  class QuotaExceededError < StandardError; end

  def initialize(limit: nil)
    @api_key = ENV["GROQ_API_KEY"]
    raise "GROQ_API_KEY environment variable not set" if @api_key.nil?

    @limit = limit
    @processed_count = 0
    @normalized_count = 0
  end

  def normalize!
    scores = fetch_scores
    total_pending = Score.where(composer_attempted: false).count
    puts "Total pending scores: #{total_pending}"
    puts "Processing: #{scores.count} unique composer fields#{@limit ? " (limited to #{@limit})" : ""}\n\n"

    process_batches(scores)
    print_summary
  end

  private

  def fetch_scores
    scores = Score.where(composer_attempted: false)
                  .distinct
                  .pluck(:composer, :title, :editor, :genres, :language)
                  .uniq { |row| row[0] }

    @limit&.positive? ? scores.first(@limit) : scores
  end

  def process_batches(remaining)
    total_batches = (remaining.count / BATCH_SIZE.to_f).ceil

    remaining.each_slice(BATCH_SIZE).with_index do |batch, idx|
      puts "Batch #{idx + 1}/#{total_batches}"

      begin
        result = groq_request(batch)
        apply_results(result)
        save_progress
      rescue QuotaExceededError
        puts "\n⚠️  Quota exceeded! Progress saved. Run again later."
        break
      end

      sleep BATCH_DELAY unless idx == total_batches - 1
    end
  end

  def apply_results(results)
    results&.each do |item|
      original = item["original"]
      normalized = item["normalized"]

      scores_to_update = Score.where(composer: original, composer_attempted: false)
      count = scores_to_update.count

      if normalized
        scores_to_update.update_all(
          composer: normalized,
          composer_normalized: true,
          composer_attempted: true
        )
        puts "  [#{count}] #{original[0..30].ljust(33)} -> #{normalized}"
        @normalized_count += count
      else
        scores_to_update.update_all(
          composer_normalized: false,
          composer_attempted: true
        )
        puts "  [#{count}] #{original[0..30].ljust(33)} -> (unknown, not normalizable)"
      end

      @processed_count += count
    end
  end

  def save_progress
    # Progress is now saved in the database via composer_normalized flag
    # No need for AppSetting cache
  end

  def print_summary
    total_pending = Score.where(composer_attempted: false).count
    total_normalized = Score.where(composer_normalized: true).count
    total_unknown = Score.where(composer_attempted: true, composer_normalized: false).count

    puts "\n#{"=" * 50}"
    puts "Scores processed this run: #{@processed_count}"
    puts "  - Successfully normalized: #{@normalized_count}"
    puts "  - Unknown (not normalizable): #{@processed_count - @normalized_count}"
    puts "\nDatabase totals:"
    puts "  - Normalized: #{total_normalized}"
    puts "  - Unknown: #{total_unknown}"
    puts "  - Pending: #{total_pending}"
    puts "\nRun again with LIMIT=<number> to continue in controlled batches."
  end

  def groq_request(batch)
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

      Return ONLY valid JSON (no markdown, no code blocks): [{"original": "composer field value", "normalized": "LastName, FirstName" or null}]
    PROMPT

    {
      model: MODEL,
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
    req["Authorization"] = "Bearer #{@api_key}"
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
    text = body.dig("choices", 0, "message", "content")

    unless text
      puts "  No text in response: #{body.keys}"
      return nil
    end

    puts "\n=== DEBUG: Groq Response ===" if ENV["DEBUG"]
    puts text[0..500] if ENV["DEBUG"]
    puts "=== END DEBUG ===\n" if ENV["DEBUG"]

    # Parse the JSON array from the response
    parsed = JSON.parse(text)

    # Handle if Groq wrapped it in an object with a key
    parsed.is_a?(Array) ? parsed : parsed.values.first
  rescue JSON::ParserError => e
    puts "  JSON parse error: #{e.message}"
    puts "  Response text: #{text[0..500]}" if text
    nil
  rescue => e
    puts "  Error: #{e.class} - #{e.message}"
    nil
  end
end
