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
      Task: Identify the classical music COMPOSER for each score entry.

      Input fields (use ALL to identify composer):
      - composer: may contain composer, arranger, title, or garbage data
      - title: often contains composer name ("Sonata by Mozart", "Bach - Prelude")
      - editor: might be arranger (original composer could be famous)
      - genres/language: hints for likely composers

      Output format - JSON array:
      [{"original": "<exact composer field value>", "normalized": "<LastName, FirstName>" or null}]

      Normalization rules:
      - Format: "LastName, FirstName" (e.g., "Bach, Johann Sebastian")
      - Use standard musicological Latin-alphabet spelling
      - Expand abbreviations: "J.S. Bach" → "Bach, Johann Sebastian"
      - Use well-known forms: "Mozart, Wolfgang Amadeus", "Beethoven, Ludwig van"
      - Tchaikovsky → "Tchaikovsky, Pyotr Ilyich" (standard English transliteration)
      - Handel → "Handel, George Frideric" (his Anglicized name he used professionally)

      Return null for:
      - Anonymous, Traditional, Folk (no known composer)
      - "Various", "Various Artists", compilations
      - Truly unidentifiable or garbage data
      - Arrangers/editors when original composer unknown

      Important:
      - "original" must be the EXACT input composer field value
      - Only identify the ORIGINAL composer, not arrangers
      - When uncertain, return null rather than guess

      Input: #{scores_data.to_json}
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
