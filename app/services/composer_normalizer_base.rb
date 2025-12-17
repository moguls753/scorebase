# frozen_string_literal: true

require "net/http"
require "json"

# Base class for composer normalization with a clean 3-phase flow:
#
# Phase 1: Pattern matches (anonymous/traditional/folk) → mark failed, cache with nil
# Phase 2: Cache hits → apply cached normalized names
# Phase 3: API calls → for remaining uncached scores
#
# Quota handling: on API quota exceeded, remaining scores stay pending (no changes)
#
class ComposerNormalizerBase
  BATCH_SIZE = 100
  BATCH_DELAY = 4

  class QuotaExceededError < StandardError; end

  def initialize(limit: nil)
    @limit = limit
    @stats = { pattern_matched: 0, cache_hits: 0, api_normalized: 0, api_failed: 0 }
  end

  def normalize!
    puts "Provider: #{provider_name}"
    puts "Pending scores: #{Score.pending.count}\n\n"

    # Phase 1: Pattern matches → failed (no API needed)
    process_unnormalizable_patterns

    # Phase 2: Apply cached mappings (no API needed)
    apply_cached_mappings

    # Phase 3: API calls for remaining uncached scores
    process_with_api

    print_summary
  end

  def provider_name
    raise NotImplementedError
  end

  private

  # ==========================================================================
  # Phase 1: Pattern Matches
  # ==========================================================================

  def process_unnormalizable_patterns
    composers = pending_composers.select { |c| ComposerMapping.known_unnormalizable?(c) }
    return if composers.empty?

    puts "Phase 1: Processing #{composers.count} unnormalizable patterns..."

    composers.each do |composer|
      # Cache the nil result
      ComposerMapping.register(original: composer, normalized: nil, source: "pattern")

      # Mark scores as failed (composer field unchanged)
      count = Score.pending.where(composer: composer).update_all(normalization_status: "failed")
      @stats[:pattern_matched] += count
    end

    puts "  → Marked #{@stats[:pattern_matched]} scores as failed (anonymous/traditional/folk/etc.)\n\n"
  end

  # ==========================================================================
  # Phase 2: Cached Mappings
  # ==========================================================================

  def apply_cached_mappings
    # Find pending composers that have cached mappings
    composers = pending_composers.select { |c| ComposerMapping.processed?(c) }
    return if composers.empty?

    puts "Phase 2: Applying #{composers.count} cached mappings..."

    composers.each do |composer|
      mapping = ComposerMapping.find_by(original_name: composer)
      scores = Score.pending.where(composer: composer)

      count = if mapping.normalized_name
        scores.update_all(composer: mapping.normalized_name, normalization_status: "normalized")
      else
        scores.update_all(normalization_status: "failed")
      end
      @stats[:cache_hits] += count
    end

    puts "  → Applied cached results to #{@stats[:cache_hits]} scores\n\n"
  end

  # ==========================================================================
  # Phase 3: API Processing
  # ==========================================================================

  def process_with_api
    # Get remaining uncached scores (with all fields for AI context)
    scores = Score.pending
                  .distinct
                  .pluck(:composer, :title, :editor, :genres, :language)
                  .uniq { |row| row[0] }
                  .reject { |row| ComposerMapping.processed?(row[0]) }

    scores = scores.first(@limit) if @limit&.positive?

    return if scores.empty?

    puts "Phase 3: Processing #{scores.count} scores with API..."
    process_batches(scores)
  end

  def process_batches(scores)
    total_batches = (scores.count / BATCH_SIZE.to_f).ceil

    scores.each_slice(BATCH_SIZE).with_index do |batch, idx|
      puts "  Batch #{idx + 1}/#{total_batches}"

      begin
        results = request_batch(batch)
        apply_api_results(results)
      rescue QuotaExceededError
        puts "\n  ⚠ Quota exceeded! Remaining #{scores.count - (idx * BATCH_SIZE)} scores left pending."
        raise
      end

      sleep BATCH_DELAY unless idx == total_batches - 1
    end
  end

  def apply_api_results(results)
    return if results.blank?

    results.each do |item|
      original = item["original"]
      normalized = item["normalized"]

      scores = Score.pending.where(composer: original)

      if normalized.present?
        ComposerMapping.register(original: original, normalized: normalized, source: provider_name)
        count = scores.update_all(composer: normalized, normalization_status: "normalized")
        @stats[:api_normalized] += count
        puts "    [#{count}] #{truncate(original, 30)} → #{normalized}"
      else
        # Don't cache nil from AI - allows retry with better prompts or different provider
        count = scores.update_all(normalization_status: "failed")
        @stats[:api_failed] += count
        puts "    [#{count}] #{truncate(original, 30)} → (unidentified)"
      end
    end
  end

  def request_batch(_batch)
    raise NotImplementedError
  end

  # ==========================================================================
  # Helpers
  # ==========================================================================

  def pending_composers
    Score.pending.distinct.pluck(:composer)
  end

  def truncate(str, length)
    str.length > length ? "#{str[0...length]}..." : str.ljust(length)
  end

  def print_summary
    total = @stats.values.sum
    puts "\n#{"=" * 50}"
    puts "This run:"
    puts "  Pattern matched (failed): #{@stats[:pattern_matched]}"
    puts "  Cache hits:               #{@stats[:cache_hits]}"
    puts "  API normalized:           #{@stats[:api_normalized]}"
    puts "  API failed:               #{@stats[:api_failed]}"
    puts "  Total processed:          #{total}"
    puts "\nDatabase totals:"
    puts "  Normalized: #{Score.normalized.count}"
    puts "  Failed:     #{Score.failed.count}"
    puts "  Pending:    #{Score.pending.count}"
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
      - Preserve diacritics for Latin-alphabet names (IMSLP/Library of Congress standard)
      - Expand abbreviations: "J.S. Bach" → "Bach, Johann Sebastian"
      - Transliterate Cyrillic to standard English spellings
      - Examples of correct forms:
        - "Dvořák, Antonín" (preserve Czech háčky/čárky)
        - "Bartók, Béla" (preserve Hungarian accents)
        - "Fauré, Gabriel" (preserve French accents)
        - "Chopin, Frédéric" (preserve French accents)
        - "Tárrega, Francisco" (preserve Spanish accents)
        - "Handel, George Frideric" (Anglicized - he became British)
        - "Tchaikovsky, Pyotr" (transliterate Cyrillic)
        - "Rachmaninoff, Sergei" (American spelling)
        - "Mozart, Wolfgang Amadeus"
        - "Beethoven, Ludwig van"

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
