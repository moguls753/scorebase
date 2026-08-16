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

  # The distinct pending names are read once and handed down; each phase returns
  # what it consumed so the next never re-reads the table to find out.
  def normalize!
    puts "Provider: #{provider_name}"
    puts "Pending scores: #{Score.composer_pending.count}\n\n"

    names = pending_composers

    # Phase 1: Pattern matches → failed (no API needed)
    names -= process_unnormalizable_patterns(names)

    # Phase 2: Apply cached mappings (no API needed)
    names -= apply_cached_mappings(names)

    # Phase 3: API calls for remaining uncached scores
    process_with_api(names)

    print_summary
  end

  def provider_name
    raise NotImplementedError
  end

  private

  # ==========================================================================
  # Phase 1: Pattern Matches
  # ==========================================================================

  def process_unnormalizable_patterns(names)
    composers = names.select { |c| ComposerMapping.known_unnormalizable?(c) }
    return composers if composers.empty?

    puts "Phase 1: Processing #{composers.count} unnormalizable patterns..."

    composers.each { |composer| ComposerMapping.register(original: composer, normalized: nil, source: "pattern") }
    @stats[:pattern_matched] += mark_failed(composers)

    puts "  → Marked #{@stats[:pattern_matched]} scores as failed (anonymous/traditional/folk/etc.)\n\n"
    composers
  end

  # ==========================================================================
  # Phase 2: Cached Mappings
  # ==========================================================================

  # One UPDATE per distinct target value, not per name: a cache hit is a lookup,
  # but every update_all here rebuilds two FTS indexes under a database-wide lock.
  def apply_cached_mappings(names)
    mappings = cached_mappings(names)
    return [] if mappings.empty?

    puts "Phase 2: Applying #{mappings.count} cached mappings..."

    by_target = mappings.group_by(&:last)
    @stats[:cache_hits] += mark_failed(by_target.delete(nil)&.map(&:first) || [])
    by_target.each do |normalized, pairs|
      @stats[:cache_hits] += update_pending(pairs.map(&:first), normalized_attributes(normalized))
    end

    puts "  → Applied cached results to #{@stats[:cache_hits]} scores\n\n"
    mappings.map(&:first)
  end

  # ==========================================================================
  # Phase 3: API Processing
  # ==========================================================================

  # The limit applies to the name list, before any context row is read. Selecting
  # first and trimming afterwards materialised one row per pending score.
  def process_with_api(names)
    names = names.first(@limit) if @limit&.positive?
    return if names.empty?

    scores = context_rows(names)
    puts "Phase 3: Processing #{scores.count} scores with API..."
    process_batches(scores)
  end

  # One representative row per name for the LLM's context, chosen by SQLite's
  # bare-column GROUP BY instead of by loading every row and deduplicating.
  def context_rows(names)
    in_slices(names).flat_map do |slice|
      Score.composer_pending.where(composer: slice)
           .group(:composer)
           .pluck(:composer, :title, :editor, :genre, :language)
    end
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
      next if original.nil?

      normalized = item["normalized"]
      scores = Score.composer_pending.where(composer: original)

      if normalized.present?
        ComposerMapping.register(original: original, normalized: normalized, source: provider_name)
        count = scores.update_all(normalized_attributes(normalized))
        @stats[:api_normalized] += count
        puts "    [#{count}] #{truncate(original, 30)} → #{normalized}"
      else
        ComposerMapping.register_unidentified(original: original, source: provider_name)
        count = scores.update_all(composer_status: "failed")
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
    Score.composer_pending.distinct.pluck(:composer).compact
  end

  # [original_name, normalized_name] for the names already decided. One IN per
  # slice; the previous per-name exists? put a query on every pending composer.
  def cached_mappings(names)
    in_slices(names).flat_map do |slice|
      ComposerMapping.where(original_name: slice).pluck(:original_name, :normalized_name)
    end
  end

  def mark_failed(names)
    update_pending(names, composer_status: "failed")
  end

  def update_pending(names, attributes)
    in_slices(names).sum do |slice|
      Score.composer_pending.where(composer: slice).update_all(attributes)
    end
  end

  # SQLite has no bind placeholders here (prepared_statements is off), so an
  # unbounded IN becomes a megabyte-sized SQL string.
  IN_SLICE = 2_000

  def in_slices(names)
    names.each_slice(IN_SLICE)
  end

  # update_all skips the before_save that derives composer_search_normalized.
  def normalized_attributes(name)
    {
      composer: name,
      composer_search_normalized: Score.normalize_for_search(name),
      composer_status: "normalized"
    }
  end

  def truncate(str, length)
    return "(nil)" if str.nil?
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
    puts "  Normalized: #{Score.composer_normalized.count}"
    puts "  Failed:     #{Score.composer_failed.count}"
    puts "  Pending:    #{Score.composer_pending.count}"
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
      [{"original": "<EXACT composer field value>", "normalized": "<LastName, FirstName>" or null}]

      CRITICAL: The "original" field must be a VERBATIM COPY of the input "composer" field.
      Do NOT clean, trim, or modify it in any way. Copy it exactly, character for character,
      including URLs, garbage text, extra spaces, or anything else. Examples:
      - Input: "Tom Brierhttps://musescore.com/xyz" → original: "Tom Brierhttps://musescore.com/xyz"
      - Input: "E MajorSamuel Babcock 1800" → original: "E MajorSamuel Babcock 1800"
      - Input: "Ludwig van BeethovenArranged by Someone" → original: "Ludwig van BeethovenArranged by Someone"

      Normalization rules:
      - Format: "LastName, FirstName" (e.g., "Bach, Johann Sebastian")
      - Preserve diacritics (Dvořák, Bartók, Fauré, Chopin, Tárrega)
      - Expand abbreviations: "J.S. Bach" → "Bach, Johann Sebastian"
      - Transliterate Cyrillic to English (Tchaikovsky, Rachmaninoff)

      Return null for normalized when:
      - Anonymous, Traditional, Folk (no known composer)
      - "Various", "Various Artists", compilations
      - Truly unidentifiable or garbage data
      - Arrangers/editors when original composer unknown

      Important:
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
