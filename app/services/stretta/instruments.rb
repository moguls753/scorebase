# frozen_string_literal: true

# Turns Stretta's German scoring text into ScoreBase's English instrument
# vocabulary and a canonical voicing code (docs/stretta-import-plan.md §5).
#
#   "2 Trompeten (C), 2 Posaunen, Tuba, Orgel"  -> "Trumpet, Trombone, Tuba, Organ"
#   "gemischter Chor (SATB) a cappella"         -> voicing "SATB"
#
# The tables are derived from the catalogue by token frequency, not written from
# knowledge of German. Two of them: `ensembles` maps generic ensemble terms to a
# display name, but only an `instruments` hit counts as normalised — an ensemble
# must never let a row into an instrument hub it has no instrument for.
module Stretta
  class Instruments
    TABLE = JSON.parse(Rails.root.join("config/stretta_instruments.json").read).freeze
    TERMS = TABLE.fetch("instruments").freeze
    ENSEMBLES = TABLE.fetch("ensembles").freeze
    VOICINGS = TABLE.fetch("voicings").freeze
    # Longest key first: "women's choir" contains "men's choir".
    VOICING_KEYS_LONGEST_FIRST = VOICINGS.keys.sort_by { |key| -key.length }.freeze

    # Three traps: /x mode eats the space inside "ad lib", Ruby's \s is ASCII-only
    # where the corpus carries NBSP and U+200B, and String#strip leaves the dot on
    # "ad lib.".
    SEPARATORS = %r{[[:space:]]*(?:,|;|/|\#|&|[[:space:]]und[[:space:]]|[[:space:]]and[[:space:]]|[[:space:]]or[[:space:]]|[[:space:]]oder[[:space:]])[[:space:]]*}
    ROUND = /\([^)]*\)/
    SQUARE = /\[[^\]]*\]/
    QUANTITY = /\A[0-9]+[[:space:]]*(?:[-–][[:space:]]*[0-9]+)?[[:space:]]*\.?[[:space:]]+/
    TRAILING = /[[:space:]]+(?:ad lib\.?|ad libitum|a cappella|a capella|solo|soli|obligat|optional|opt\.|divisi|manualiter|vierhandig|4-handig|begleitung)\.?\z/
    LEADING = /\A(?:fur|for|solo for|solo|mit|with|and|und)[[:space:]]+/
    EDGE = /\A[ .\-–]+|[ .\-–]+\z/

    AFFIX_PASSES = 3

    # Stretta's ensembles onto the ensemble hubs. Every target must exist in
    # HubDataBuilder::ENSEMBLE_CATEGORIES or the rows land in a category with no
    # page — a spec asserts exactly that.
    ENSEMBLE_HUBS = {
      "wind band" => "Concert Band",
      "orchestra" => "Orchestra",
      "string orchestra" => "Orchestra",
      "jazz ensemble" => "Jazz Ensemble",
      "marching band" => "Marching Band",
      "guitar ensemble" => "Guitar Ensemble",
      "chamber ensemble" => "Chamber Ensemble"
    }.freeze

    # The display vocabulary keeps one English term per German token family, which
    # for brass is coarser than the hubs need: it calls a quintet a brass band.
    # Hub classification therefore reads the token for this one family.
    BRASS_BAND_TOKENS = ["brass band", "posaunenchor", "posaunenchore"].freeze

    CHOIR_CODES = %w[SATB SSA SAB TTBB SSAA TB TBB].freeze

    VOICING_CODE = /\A[SATB]{3,8}\z/

    # Gating the bracket test on a vocal word in the row takes its false positives
    # from 4.22% to 0.09% — the error class is consorts, where "4 Blockflöten
    # (SATB)" names recorder sizes, not voices. The abbreviations come from the
    # rows the gate would otherwise lose (`GCH (SATB)`, `FCH (SSA)`).
    VOCAL = /chor|choir|stimme|voice|vocal|gesang|chorus|vokal|coro|canto|schola|soloist|cantor|sing|kantor|gemeinde|congregation|\b(?:gch|fch|mch|kch|ges)\b/

    class << self
      # Distinct English terms, in first-appearance order, or nil when nothing maps.
      # Capitalised to match how the rest of the catalogue stores instruments; the
      # FTS index lowercases, so this is display only.
      def parse(text)
        terms = lookup(text, TERMS) | lookup(text, ENSEMBLES)
        return nil if terms.empty?

        terms.map { |term| term.split.map(&:capitalize).join(" ") }.join(", ")
      end

      # True only when a term from VALID_INSTRUMENTS was found. An ensemble alone
      # leaves the row pending, so it stays fixable rather than counting as done.
      def normalized?(text)
        lookup(text, TERMS).any?
      end

      # Canonical code or nil. Never German plain text: the voicing scopes match with
      # LIKE, and SQLite's LIKE is ASCII case-insensitive, so 'gemischter Chor'
      # LIKE '%S%' is true and would file the row under every voice type at once.
      def voicing(text)
        return nil if text.blank?

        folded = fold(text)
        if folded.match?(VOCAL)
          text.scan(ROUND) do |bracket|
            code = bracket[1..-2].to_s.strip.upcase
            return code if code.match?(VOICING_CODE)
          end
        end

        VOICING_KEYS_LONGEST_FIRST.each do |ensemble|
          return VOICINGS[ensemble] if folded.include?(ensemble)
        end
        nil
      end

      # The ensemble hub this scoring belongs to, or nil. Values come out of
      # HubDataBuilder::ENSEMBLE_CATEGORIES, the curated allowlist those hubs are
      # built from — §3 says not to *silently* file Stretta into them, and this is
      # the opposite: an explicit mapping onto categories that already exist.
      #
      # Choir first: a choral work with orchestra is a choral work.
      def hub_category(scoring)
        ensembles = lookup(scoring, ENSEMBLES)

        if ensembles.include?("choir")
          code = voicing(scoring)
          return CHOIR_CODES.include?(code) ? "#{code} Choir" : "Choir"
        end
        return brass_category(scoring) if ensembles.include?("brass band")

        ensembles.filter_map { |ensemble| ENSEMBLE_HUBS[ensemble] }.first
      end

      def tokens(text)
        return [] if text.blank?

        text.gsub(ROUND, " ").gsub(SQUARE, " ")
            .split(SEPARATORS, -1)
            .map { |part| strip_affixes(fold(part.strip.sub(QUANTITY, ""))) }
            .reject(&:empty?)
            .uniq
      end

      private

      def brass_category(scoring)
        tokens(scoring).intersect?(BRASS_BAND_TOKENS) ? "Brass Band" : "Brass Ensemble"
      end

      def lookup(text, table)
        tokens(text).filter_map { |token| table[token] }.uniq
      end

      def fold(text)
        text.downcase.gsub("ß", "ss").unicode_normalize(:nfd).gsub(/\p{Mn}/, "")
            .gsub(/[[:space:]]+/, " ").gsub(EDGE, "")
      end

      def strip_affixes(part)
        AFFIX_PASSES.times do
          stripped = part.sub(TRAILING, "").sub(LEADING, "")
          break if stripped == part

          part = stripped
        end
        part
      end
    end
  end
end
