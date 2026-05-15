# frozen_string_literal: true

# Phase 2 of SMD enrichment. Flips status fields and fills derived columns
# (has_vocal, voicing, pedagogical_grade, genre) deterministically. Pure
# Ruby. Runs after SmdVisionExtractor has set extraction_status to
# :vision_extracted.
class SmdStatusNormalizer
  Result = Struct.new(:status, :score, :changes, :reason, keyword_init: true)

  PLACEHOLDER_COMPOSERS = SearchTextGenerator::COMPOSER_PLACEHOLDERS

  VOCAL_KEYWORDS = /\b(choir|choral|voice|vocal|satb|ssa|ssaa|ttbb|chorus|sacred|
                     hymn|hymne|hymnen|gospel|spiritual|anthem|aria|
                     lied|kantate|cantata)\b/ix

  # Longer patterns first so SATB doesn't pre-match against SSATB / SAATB.
  VOICING_PATTERNS = [
    [/\bSSAATB\b/i, "SSAATB"], [/\bSAATB\b/i,  "SAATB"],
    [/\bSSATB\b/i,  "SSATB"],  [/\bSATB\b/i,   "SATB"],
    [/\bSSAA\b/i,   "SSAA"],   [/\bSSA\b/i,    "SSA"],
    [/\bTTBB\b/i,   "TTBB"],   [/\bTTB\b/i,    "TTB"],
    [/\bSAB\b/i,    "SAB"],
    [/\b2[\s-]?Part\b/i, "2-Part"],
    [/\b3[\s-]?Part\b/i, "3-Part"],
    [/\bUnison\b/i, "Unison"]
  ].freeze

  LEVEL_PATTERNS = [
    [/\b(super\s+easy|big\s+note|beginning|early\s+beginner|elementary\s+1)\b/i, "beginner"],
    [/\b(easy|e-z\s+play|late\s+beginner)\b/i, "elementary"],
    [/\bintermediate\b/i, "intermediate"],
    [/\b(advanced|virtuoso)\b/i, "advanced"]
  ].freeze

  # Patterns accept singular + plural (English `s`, plus `-es` for sibilants
  # and `-ies` for `y` endings). Lied excluded: collides with English
  # past-tense verb "lied".
  GENRE_TITLE_PATTERNS = [
    [/\bsonatinas?\b/i,       "Sonatina"], [/\bsonatas?\b/i,    "Sonata"],
    [/\bfugues?\b/i,          "Fugue"],    [/\btoccatas?\b/i,   "Toccata"],
    [/\bpreludes?\b/i,        "Prelude"],
    [/\bmass(?:es)?\b(?!\s*choir)/i, "Mass"],
    [/\bmotets?\b/i,          "Motet"],    [/\bcantatas?\b/i,   "Cantata"],
    [/\bconcertos?\b/i,       "Concerto"],
    [/\bsymphon(?:y|ies)\b/i, "Symphony"],
    [/\bsuites?\b/i,          "Suite"],    [/\barias?\b/i,      "Aria"],
    [/\bhymns?\b/i,           "Hymn"],     [/\banthems?\b/i,    "Anthem"],
    [/\bcarols?\b/i,          "Carol"],    [/\bchorales?\b/i,   "Chorale"],
    [/\betudes?\b/i,          "Etude"],    [/\bnocturnes?\b/i,  "Nocturne"],
    [/\bwaltz(?:es)?\b/i,     "Waltz"],    [/\bmazurkas?\b/i,   "Mazurka"],
    [/\brondos?\b/i,          "Rondo"],    [/\bscherzos?\b/i,   "Scherzo"],
    [/\bmarch(?:es)?\b/i,     "March"],    [/\bpolonaises?\b/i, "Polonaise"],
    [/\bbagatelles?\b/i,      "Bagatelle"]
  ].freeze

  GENRE_TAG_PATTERNS = [
    [/Christmas/i,    "Carol"],
    [/\bGospel\b/i,   "Gospel"],
    [/\bSpiritual\b/i, "Spiritual"]
  ].freeze

  STATUS_FIELDS = %i[composer_status period_status instruments_status
                     has_vocal_status voicing_status grade_status
                     genre_status].freeze

  def self.fully_normalized?(score)
    STATUS_FIELDS.all? { |f| score.public_send(f) != "pending" }
  end

  def initialize(score)
    @score = score
    @updates = {}
  end

  def call
    return skipped("not SMD")            unless @score.source == "smd"
    return skipped("vision not yet run") unless @score.extraction_vision_extracted?
    return skipped("already normalized") if self.class.fully_normalized?(@score)

    determine_composer_status
    determine_period_status
    determine_instruments_status
    determine_has_vocal
    determine_voicing
    determine_grade
    determine_genre

    @score.update!(@updates) if @updates.any?
    Result.new(status: :ok, score: @score, changes: @updates, reason: nil)
  end

  private

  def skipped(reason)
    Result.new(status: :skipped, score: @score, changes: {}, reason: reason)
  end

  def determine_composer_status
    composer = @score.composer.to_s
    valid = composer.present? && PLACEHOLDER_COMPOSERS.none? { |p| composer.casecmp?(p) }
    @updates[:composer_status] = valid ? "normalized" : "not_applicable"
  end

  # Defensive: importer (lib/smd_crawler/crawler.rb:59) already sets
  # period_status = "normalized" at import time for SMD. This branch
  # almost never fires.
  def determine_period_status
    return unless @score.period_status == "pending"

    @updates[:period_status] = @score.period.present? ? "normalized" : "not_applicable"
  end

  def determine_instruments_status
    @updates[:instruments_status] = @score.instruments.present? ? "normalized" : "not_applicable"
  end

  def determine_has_vocal
    keyword_text = [@score.arrangement_category, @score.smd_category,
                    @score.instruments, @score.tags].compact.join(" ").downcase
    keyword_vocal = keyword_text.match?(VOCAL_KEYWORDS)
    vision_vocal = @score.has_vocal == true

    @updates[:has_vocal] = keyword_vocal || vision_vocal
    @updates[:has_vocal_status] = "normalized"
  end

  def determine_voicing
    unless @updates[:has_vocal]
      @updates[:voicing_status] = "not_applicable"
      return
    end

    candidate = [@score.arrangement_category, @score.smd_category, @score.part_names].compact.join(" ")
    match = VOICING_PATTERNS.find { |pat, _| candidate.match?(pat) }
    if match
      @updates[:voicing] = match[1]
      @updates[:voicing_status] = "normalized"
      return
    end

    derived = derive_voicing_from_part_names(@score.part_names)
    if derived
      @updates[:voicing] = derived
      @updates[:voicing_status] = "normalized"
    else
      # Vocal but unparseable. Leave voicing nil, status pending so a
      # later manual pass or richer vision data can backfill.
      @updates[:voicing_status] = "pending"
    end
  end

  def determine_grade
    # Idempotency: importer (lib/smd_crawler/crawler.rb:46) already fills
    # pedagogical_grade for super_easy / easy categories. Never overwrite.
    if @score.pedagogical_grade.present?
      @updates[:grade_status] = "normalized"
      return
    end

    cat = @score.smd_category.to_s
    match = LEVEL_PATTERNS.find { |pat, _| cat.match?(pat) }
    unless match
      @updates[:grade_status] = "not_applicable"
      return
    end

    level = match[1]
    grade = Score::DIFFICULTY_LEVELS[level]&.first
    if grade
      @updates[:pedagogical_grade] = grade
      @updates[:grade_status] = "normalized"
    else
      @updates[:grade_status] = "not_applicable"
    end
  end

  def determine_genre
    genre = match_genre(GENRE_TITLE_PATTERNS, @score.title) ||
            match_genre(GENRE_TAG_PATTERNS, @score.tags)

    if genre
      @updates[:genre] = genre
      @updates[:genre_status] = "normalized"
    else
      @updates[:genre_status] = "not_applicable"
    end
  end

  def match_genre(patterns, text)
    return nil if text.blank?

    patterns.each do |pat, form|
      return form if text.to_s.match?(pat)
    end
    nil
  end

  # Derive SATB-style voicing from named parts when no canonical voicing
  # abbreviation is in the arrangement strings. Example:
  #   "Tenor I, Tenor II, Baritone, Bass" => "TTBB"
  #   "Soprano, Alto, Tenor, Bass, Piano" => "SATB"
  def derive_voicing_from_part_names(part_names)
    return nil if part_names.blank?

    counts = { s: 0, a: 0, t: 0, b: 0 }
    part_names.split(",").each do |raw|
      p = raw.strip.downcase
      counts[:s] += 1 if p.match?(/\bsoprano\b/i)
      counts[:a] += 1 if p.match?(/\b(alto|contralto|countertenor|mezzo)\b/i)
      counts[:t] += 1 if p.match?(/\btenor\b/i)
      counts[:b] += 1 if p.match?(/\b(bass|baritone)\b/i)
    end

    voicing = ("S" * counts[:s]) + ("A" * counts[:a]) +
              ("T" * counts[:t]) + ("B" * counts[:b])
    voicing.length >= 2 ? voicing : nil
  end
end
