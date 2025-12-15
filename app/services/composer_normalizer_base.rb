# frozen_string_literal: true

require "net/http"
require "json"

class ComposerNormalizerBase
  BATCH_SIZE = 100
  BATCH_DELAY = 4

  class QuotaExceededError < StandardError; end

  def initialize(limit: nil)
    @limit = limit
    @processed_count = 0
    @normalized_count = 0
  end

  def normalize!
    scores = fetch_scores
    total_pending = Score.pending.count
    puts "Total pending scores: #{total_pending}"
    puts "Processing: #{scores.count} unique composer fields#{@limit ? " (limited to #{@limit})" : ""}"
    puts "Provider: #{provider_name}\n\n"

    process_batches(scores)
    print_summary
  end

  def provider_name
    raise NotImplementedError
  end

  private

  def fetch_scores
    scores = Score.pending
                  .distinct
                  .pluck(:composer, :title, :editor, :genres, :language)
                  .uniq { |row| row[0] }

    scores = scores.reject { |row| ComposerMapping.attempted?(row[0]) }
    @limit&.positive? ? scores.first(@limit) : scores
  end

  def process_batches(remaining)
    total_batches = (remaining.count / BATCH_SIZE.to_f).ceil

    remaining.each_slice(BATCH_SIZE).with_index do |batch, idx|
      puts "Batch #{idx + 1}/#{total_batches}"

      result = request_batch(batch)
      apply_results(result)

      sleep BATCH_DELAY unless idx == total_batches - 1
    end
  rescue QuotaExceededError
    puts "\nQuota exceeded! Progress saved."
    raise # Re-raise for ComposerNormalizer to catch
  end

  def request_batch(batch)
    raise NotImplementedError
  end

  def apply_results(results)
    results&.each do |item|
      original = item["original"]
      normalized = item["normalized"]

      ComposerMapping.register(
        original: original,
        normalized: normalized,
        source: provider_name
      )

      scores_to_update = Score.pending.where(composer: original)
      count = scores_to_update.count

      if normalized
        scores_to_update.update_all(
          composer: normalized,
          normalization_status: "normalized"
        )
        puts "  [#{count}] #{original[0..30].ljust(33)} -> #{normalized}"
        @normalized_count += count
      else
        scores_to_update.update_all(normalization_status: "failed")
        puts "  [#{count}] #{original[0..30].ljust(33)} -> (unknown)"
      end

      @processed_count += count
    end
  end

  def print_summary
    puts "\n#{"=" * 50}"
    puts "Scores processed this run: #{@processed_count}"
    puts "  - Normalized: #{@normalized_count}"
    puts "  - Unknown: #{@processed_count - @normalized_count}"
    puts "\nDatabase totals:"
    puts "  - Normalized: #{Score.normalized.count}"
    puts "  - Unknown: #{Score.failed.count}"
    puts "  - Pending: #{Score.pending.count}"
  end

  def build_prompt(scores_data)
    <<~PROMPT
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
      - "Tchaikovsky" -> "Tschaikowski, Pjotr Iljitsch" (use Latin script)
      - If composer field is garbage but title hints at composer -> extract it
      - Traditional/folk music with no known composer -> null
      - If truly unknown -> null

      Input: #{scores_data.to_json}

      Return ONLY valid JSON: [{"original": "composer field value", "normalized": "LastName, FirstName" or null}]
    PROMPT
  end

  def send_http_request(uri, payload, headers = {})
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.read_timeout = 60

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    headers.each { |k, v| req[k] = v }
    req.body = payload.to_json

    http.request(req)
  end
end
