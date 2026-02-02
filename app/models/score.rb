# == Schema Information
#
# Table name: scores
#
#  id                         :integer          not null, primary key
#  accidental_count           :integer
#  ambitus_semitones          :integer
#  arpeggio_mark_count        :integer
#  arrangement_category       :string
#  artist                     :string
#  avg_chord_span             :float
#  beat_count                 :integer
#  brand                      :string
#  cadence_types              :text
#  chord_count                :integer
#  chromatic_note_count       :integer
#  chromatic_ratio            :float
#  clean_title                :string
#  clefs_used                 :text
#  complexity                 :integer
#  composer                   :string
#  composer_normalized        :string
#  composer_status            :string           default("pending"), not null
#  computed_difficulty        :integer
#  contrary_motion_ratio      :float
#  contributors               :json
#  cpdl_number                :string
#  data_path                  :string
#  deleted_at                 :datetime
#  description                :text
#  detected_instruments       :text
#  duration_seconds           :float
#  dynamic_range              :string
#  editor                     :string
#  estimated_duration_seconds :float
#  estimated_tempo_bpm        :integer
#  event_count                :integer
#  expression_markings        :text
#  external_url               :string
#  extracted_at               :datetime
#  extracted_lyrics           :text
#  extraction_error           :text
#  extraction_status          :string           default("pending"), not null
#  favorites                  :integer          default(0)
#  final_cadence              :string
#  form_analysis              :string
#  genre                      :text
#  genre_status               :string           default("pending"), not null
#  grace_note_count           :integer
#  grade_source               :string
#  grade_status               :string           default("pending"), not null
#  group_key                  :string
#  harmonic_rhythm            :float
#  has_accompaniment          :boolean
#  has_articulations          :boolean
#  has_dynamics               :boolean
#  has_extracted_lyrics       :boolean
#  has_fermatas               :boolean
#  has_ornaments              :boolean
#  has_ottava                 :boolean
#  has_pedal_marks            :boolean
#  has_tempo_changes          :boolean
#  has_vocal                  :boolean
#  has_vocal_status           :string           default("pending"), not null
#  highest_pitch              :string
#  index_version              :integer
#  indexed_at                 :datetime
#  instrument_families        :text
#  instruments                :string
#  instruments_status         :string           default("pending"), not null
#  interval_count             :integer
#  interval_distribution      :json
#  is_arrangeme               :boolean
#  is_group_representative    :boolean
#  is_instrumental            :boolean
#  is_interactive             :boolean
#  is_multi_movement          :boolean
#  key_confidence             :float
#  key_correlations           :json
#  key_signature              :string
#  language                   :string
#  largest_interval           :integer
#  leap_count                 :integer
#  leaps_per_measure          :float
#  license                    :string
#  lowest_pitch               :string
#  lyrics                     :text
#  lyrics_language            :string
#  main_instrument            :string
#  max_chord_span             :integer
#  measure_count              :integer
#  melodic_complexity         :float
#  melodic_contour            :string
#  metadata_path              :string
#  meter_classification       :string
#  mid_path                   :string
#  modulation_count           :integer
#  modulation_targets         :json
#  modulations                :text
#  mordent_count              :integer
#  music21_version            :string
#  musicxml_source            :string
#  mxl_path                   :string
#  note_density               :float
#  num_parts                  :integer
#  oblique_motion_ratio       :float
#  off_beat_count             :integer
#  original_price_usd         :decimal(8, 2)
#  page_count                 :integer
#  parallel_motion_ratio      :float
#  part_names                 :text
#  pdf_path                   :string
#  pedagogical_grade          :string
#  pedagogical_grade_de       :string
#  period                     :string
#  period_status              :string           default("pending"), not null
#  pitch_class_distribution   :json
#  pitch_count                :integer
#  pitch_range                :string
#  pitch_range_per_part       :json
#  posted_date                :date
#  predominant_rhythm         :string
#  preview_image_url          :string
#  price_usd                  :decimal(8, 2)
#  rag_status                 :string           default("pending"), not null
#  rating                     :decimal(3, 2)
#  repeats_count              :integer
#  review_count               :integer
#  rhythm_distribution        :json
#  rhythmic_variety           :float
#  search_text                :text
#  search_text_generated_at   :datetime
#  sections_count             :integer
#  simultaneous_note_avg      :float
#  slur_count                 :integer
#  smd_category               :string
#  source                     :string           default("pdmx")
#  stepwise_count             :integer
#  stepwise_motion_ratio      :float
#  syllable_count             :integer
#  syncopation_level          :float
#  tags                       :text
#  tempo_bpm                  :integer
#  tempo_marking              :string
#  tempo_referent             :float
#  tessitura                  :json
#  texture_type               :string
#  texture_variation          :float
#  thumbnail_url              :string
#  time_signature             :string
#  title                      :string
#  title_normalized           :string
#  total_quarter_length       :float
#  tremolo_count              :integer
#  trill_count                :integer
#  turn_count                 :integer
#  unique_chord_count         :integer
#  unique_duration_count      :integer
#  unique_pitches             :integer
#  vertical_density           :float
#  views                      :integer          default(0)
#  voice_independence         :float
#  voice_ranges               :json
#  voicing                    :string
#  voicing_status             :string           default("pending"), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  external_id                :string
#
# Indexes
#
#  index_scores_active_by_created_at             (created_at) WHERE deleted_at IS NULL
#  index_scores_on_ambitus_semitones             (ambitus_semitones)
#  index_scores_on_artist                        (artist)
#  index_scores_on_brand                         (brand)
#  index_scores_on_chromatic_ratio               (chromatic_ratio)
#  index_scores_on_complexity                    (complexity)
#  index_scores_on_composer                      (composer)
#  index_scores_on_composer_normalized           (composer_normalized)
#  index_scores_on_composer_status               (composer_status)
#  index_scores_on_computed_difficulty           (computed_difficulty)
#  index_scores_on_created_at                    (created_at)
#  index_scores_on_deleted_at                    (deleted_at)
#  index_scores_on_duration_seconds              (duration_seconds)
#  index_scores_on_event_count                   (event_count)
#  index_scores_on_external_id                   (external_id)
#  index_scores_on_extraction_status             (extraction_status)
#  index_scores_on_genre                         (genre)
#  index_scores_on_genre_status                  (genre_status)
#  index_scores_on_genre_status_and_lower_genre  (genre_status, LOWER(genre))
#  index_scores_on_grade_status                  (grade_status)
#  index_scores_on_group_key                     (group_key)
#  index_scores_on_has_extracted_lyrics          (has_extracted_lyrics)
#  index_scores_on_has_vocal                     (has_vocal)
#  index_scores_on_has_vocal_status              (has_vocal_status)
#  index_scores_on_highest_pitch                 (highest_pitch)
#  index_scores_on_indexed_at                    (indexed_at)
#  index_scores_on_instruments                   (instruments)
#  index_scores_on_instruments_status            (instruments_status)
#  index_scores_on_is_arrangeme                  (is_arrangeme)
#  index_scores_on_is_group_representative       (is_group_representative) WHERE is_group_representative = 1
#  index_scores_on_key_confidence                (key_confidence)
#  index_scores_on_key_signature                 (key_signature)
#  index_scores_on_lowest_pitch                  (lowest_pitch)
#  index_scores_on_measure_count                 (measure_count)
#  index_scores_on_melodic_complexity            (melodic_complexity)
#  index_scores_on_modulation_count              (modulation_count)
#  index_scores_on_num_parts                     (num_parts)
#  index_scores_on_pedagogical_grade             (pedagogical_grade)
#  index_scores_on_period                        (period)
#  index_scores_on_period_status                 (period_status)
#  index_scores_on_price_usd                     (price_usd)
#  index_scores_on_rag_status                    (rag_status)
#  index_scores_on_rating                        (rating)
#  index_scores_on_source                        (source)
#  index_scores_on_tempo_bpm                     (tempo_bpm)
#  index_scores_on_texture_type                  (texture_type)
#  index_scores_on_time_signature                (time_signature)
#  index_scores_on_title_normalized              (title_normalized)
#  index_scores_on_views                         (views)
#  index_scores_on_voicing                       (voicing)
#  index_scores_on_voicing_status                (voicing_status)
#
class Score < ApplicationRecord
  include Thumbnailable
  include Galleried
  include PdfSyncable

  # Sources
  SOURCES = %w[pdmx cpdl imslp openscore-lieder openscore-quartets smd].freeze

  # Instrument patterns for grouping SMD ensemble parts
  INSTRUMENT_PATTERNS = [
    /^(Full |Conductor)/i,
    /^Score$/i,
    /^Piano/i,
    /^(Keyboard|Synthesizer|Synth|Organ|Electric Piano|Celesta|Electronic Keyboard)/i,
    /^(Flute|Piccolo)/i,
    /^(Clarinet|Bass Clarinet)/i,
    /^(Oboe|Bassoon|Contrabassoon|English Horn)/i,
    /^(Sax|Saxophone|Bari Sax)/i,
    /^(Trumpet|Cornet|Flugelhorn)/i,
    /^(Trombone)/i,
    /^(Horn|French Horn)/i,
    /^(Tuba|Euphonium|Baritone)/i,
    /^(Violin|Viola|Cello|Bass|Contrabass|String Bass|Double Bass|Upright Bass)/i,
    /^(Harp)/i,
    /^String[ \/](Electric|Reduction)/i,
    /^Strings /i,
    /^(Percussion|Drums|Drum Set|Timpani|Mallet|Aux|Vibes|Vibraphone)/i,
    /^(Glockenspiel|Xylophone|Marimba|Snare|Cymbals|Suspended Cymbal)/i,
    /^(Tom|Bells|Chimes|Congas|Bongos|Maracas|Claves|Tambourine)/i,
    /^(Triangle|Shaker|Cowbell|Wood ?Block|Multiple Bass|Djembe|Timbales|Cabasa|Shekere|Sleigh Bells|Cajon)/i,
    /^(Handbells|Guiro|Pitched Percussion|Un-?pitched Percussion)/i,
    /^Quad /i,
    /^(Guitar|Electric Guitar|Electric Bass|Acoustic Guitar|Capo Guitar|Lead Guitar)/i,
    /^(Voice|Vocal|Soprano|Alto|Tenor|Baritone|Choir|Chorus)/i,
    /^(SATB|SSAB|SSAA|SAB|SSA|TTBB|TB)\b/i,
    /^[23][ -]?(pt|Part)/i,
    /^(Fiddle|Mandolin|Banjo|Ukulele|Dulcimer|Recorder|Harmonica|Accordion|Dobro|Pennywhistle|Bodhran)/i,
    /^(Eb|Bb|F|C) /i,
    /^(1st|2nd|3rd|4th|[0-9]+(st|nd|rd|th)?) /i,
    /^(Orchestral|Convertible|Alternate|Alt\.|Solo|Sub\.)/i,
    /^(Rhythm|Acoustic)/i,
    /^Armonia$/i
  ].freeze

  # SMD affiliate ID for commission tracking
  SMD_AFFILIATE_ID = "67428".freeze

  # Active Storage attachments
  has_one_attached :pdf_file

  # Normalize empty strings to nil (forms often send "" instead of nil)
  normalizes :external_id, with: ->(value) { value.presence }

  # Validations
  validates :title, presence: true
  validates :data_path, uniqueness: true, allow_nil: true
  validates :external_id, uniqueness: { scope: :source }, allow_nil: true
  validates :source, inclusion: { in: SOURCES }, allow_nil: true

  # Keep normalized search columns in sync
  before_save :update_normalized_search_columns, if: -> { title_changed? || composer_changed? }

  # Pagination
  paginates_per 30

  # Source scopes
  scope :from_pdmx, -> { where(source: "pdmx") }
  scope :from_cpdl, -> { where(source: "cpdl") }
  scope :from_imslp, -> { where(source: "imslp") }
  scope :by_source, ->(source) { where(source: source) if source.present? }

  # Soft delete scopes - use Score.active in public-facing code
  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }
  scope :deleted_before, ->(date) { deleted.where("deleted_at < ?", date) }

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def restore!
    update!(deleted_at: nil)
  end

  def deleted?
    deleted_at.present?
  end

  # Status enums for normalized fields
  # All use: pending | normalized | not_applicable | failed
  enum :composer_status, {
    pending: "pending",
    normalized: "normalized",
    not_applicable: "not_applicable",
    failed: "failed"
  }, default: :pending, prefix: :composer

  enum :genre_status, {
    pending: "pending",
    normalized: "normalized",
    not_applicable: "not_applicable",
    failed: "failed"
  }, default: :pending, prefix: :genre

  enum :period_status, {
    pending: "pending",
    normalized: "normalized",
    not_applicable: "not_applicable",
    failed: "failed"
  }, default: :pending, prefix: :period

  enum :instruments_status, {
    pending: "pending",
    normalized: "normalized",
    not_applicable: "not_applicable",
    failed: "failed"
  }, default: :pending, prefix: :instruments

  enum :has_vocal_status, {
    pending: "pending",
    normalized: "normalized",
    failed: "failed"
  }, default: :pending, prefix: :has_vocal

  enum :voicing_status, {
    pending: "pending",
    normalized: "normalized",
    not_applicable: "not_applicable",
    failed: "failed"
  }, default: :pending, prefix: :voicing

  enum :grade_status, {
    pending: "pending",
    normalized: "normalized",
    not_applicable: "not_applicable",
    failed: "failed"
  }, default: :pending, prefix: :grade

  enum :extraction_status, {
    pending: "pending",
    extracted: "extracted",
    failed: "failed",
    no_musicxml: "no_musicxml"
  }, default: :pending, prefix: :extraction

  enum :rag_status, {
    pending: "pending",      # Waiting for enrichment
    ready: "ready",          # All fields validated, ready for text generation
    templated: "templated",  # search_text generated (LLM)
    indexed: "indexed",      # In vector store, searchable
    failed: "failed"         # Needs investigation
  }, default: :pending, prefix: :rag
  # Scopes for filtering
  scope :by_key_signature, ->(key) { where(key_signature: key) if key.present? }
  scope :by_time_signature, ->(time) { where(time_signature: time) if time.present? }
  scope :by_num_parts, ->(parts) { where(num_parts: parts) if parts.present? }

  # Difficulty levels - maps user-friendly names to ABRSM-style pedagogical grades
  # Grades determined by LLM analysis of known repertoire (see NormalizePedagogicalGradeJob)
  DIFFICULTY_LEVELS = {
    "beginner"     => ["Grade 1", "Grade 1-2", "Grade 2"],
    "elementary"   => ["Grade 2-3", "Grade 3", "Grade 1-3", "Grade 2-4"],
    "intermediate" => ["Grade 3-4", "Grade 4", "Grade 3-5", "Grade 4-5"],
    "advanced"     => ["Grade 5", "Grade 5-6", "Grade 4-6", "Grade 6", "Grade 5-7"],
    "expert"       => ["Grade 6-7", "Grade 7", "Grade 6-8", "Grade 7-8", "Grade 8", "Grade 5-8", "Diploma+"]
  }.freeze

  scope :by_difficulty, ->(level) {
    return all if level.blank?
    grades = DIFFICULTY_LEVELS[level.to_s]
    return none unless grades

    where(pedagogical_grade: grades)
  }

  # Length filter - based on page count
  # Short: 1-2 pages (sight reading, warm-ups, encores)
  # Medium: 3-6 pages (standard repertoire)
  # Long: 7+ pages (substantial works)
  scope :by_length, ->(length) {
    return all if length.blank?
    case length.to_s
    when "short" then where(page_count: 1..2)
    when "medium" then where(page_count: 3..6)
    when "long" then where("page_count >= ?", 7)
    else all
    end
  }

  # Genre filter - exact match on normalized genre field.
  # After normalization, genre is a single clean value (e.g., "Mass", "Hymn").
  # Allowlist in HubDataBuilder gates which genres are accessible on hub pages.
  # Uses LOWER() for case-insensitive matching.
  scope :by_genre, ->(genre_name) {
    return all if genre_name.blank?
    where(genre_status: "normalized")
      .where("LOWER(genre) = ?", genre_name.downcase)
  }

  # Period filter - maps canonical period names to LLM output variants.
  # e.g., "Modern" matches ["Modern", "Contemporary", "20th Century", ...]
  scope :by_period, ->(period_name) {
    return all if period_name.blank?
    variants = HubDataBuilder::PERIODS[period_name]
    return none unless variants

    where(period: variants)
  }

  # Instrument filter for hub pages (uses FTS5 trigram index for fast substring matching)
  scope :by_instrument, ->(instrument_name) {
    return all if instrument_name.blank?
    fts_query = build_fts5_query(instrument_name)
    return all if fts_query.blank?
    where("id IN (SELECT rowid FROM scores_instruments_fts WHERE instruments MATCH ?)", fts_query)
  }

  # Pricing filter: free (public domain) vs commercial (SMD with price)
  scope :by_pricing, ->(pricing) {
    case pricing
    when "free"
      where("source != 'smd' OR price_usd IS NULL OR price_usd <= 0")
    when "commercial"
      where(source: "smd").where("price_usd > 0")
    else
      all
    end
  }

  # Christmas filter for seasonal landing pages
  # Searches both tags and title for christmas keywords
  scope :christmas, -> {
    where("LOWER(tags) LIKE '%christmas%' OR LOWER(title) LIKE '%christmas%'")
  }

  # SATB choir filter (for Christmas choir page)
  scope :satb_choir, -> {
    where("instruments LIKE '%SATB%' OR voicing LIKE '%SATB%'")
  }

  # Scoped search by title (case-insensitive, for composer page filtering)
  # Uses FTS5 trigram index for fast substring matching
  scope :search_by_title, ->(query) {
    return all if query.blank?
    fts_query = build_fts5_query(query)
    return all if fts_query.blank?
    where("id IN (SELECT rowid FROM scores_search_fts WHERE title MATCH ?)", fts_query)
  }

  # Forces filters (maps UI labels to num_parts)
  scope :solo, -> { where(num_parts: 1) }
  scope :duet, -> { where(num_parts: 2) }
  scope :trio, -> { where(num_parts: 3) }
  scope :quartet, -> { where(num_parts: 4) }
  scope :ensemble, -> { where("num_parts >= ?", 5) }

  # Voice type filters (choir type based on voicing field)
  # Mixed: contains both soprano/alto AND tenor/bass voices (SATB, SAB, SATBB, etc.)
  scope :mixed_voices, -> { where("voicing LIKE '%S%' AND (voicing LIKE '%T%' OR voicing LIKE '%B%')") }
  # Treble/Women's: only soprano/alto, no tenor/bass (SA, SSA, SSAA)
  scope :treble_voices, -> { where("voicing LIKE '%S%' AND voicing LIKE '%A%' AND voicing NOT LIKE '%T%' AND voicing NOT LIKE '%B%'") }
  # Men's: only tenor/bass, no soprano/alto (TB, TTB, TTBB)
  scope :mens_voices, -> { where("(voicing LIKE '%T%' OR voicing LIKE '%B%') AND voicing NOT LIKE '%S%' AND voicing NOT LIKE '%A%'") }
  # Unison: single melodic line
  scope :unison_voices, -> { where("LOWER(voicing) LIKE '%unison%' OR num_parts = 1") }

  # Search scope using normalized columns for accent-insensitive search
  # "Etudes" matches "Études", "Dvorak" matches "Dvořák"
  # Uses FTS5 trigram index for fast substring matching across title, composer, genre
  # AND matching: all words must appear (in any order)
  #
  # Group-aware: when a part matches (e.g., "Birds of a Feather - Bass"), returns
  # the group representative (Full Score) instead. This ensures search results show
  # one card per arrangement, not 20 cards for each part.
  scope :search, ->(query) {
    return all if query.blank?
    fts_query = build_fts5_query(query)
    return all if fts_query.blank?

    # Subquery for FTS matches
    fts_match = "SELECT rowid FROM scores_search_fts WHERE scores_search_fts MATCH #{connection.quote(fts_query)}"

    where(<<~SQL.squish)
      /* Ungrouped matches: include directly */
      (id IN (#{fts_match}) AND group_key IS NULL)
      OR
      /* Grouped matches: include only the representative for each matching group */
      id IN (
        SELECT (
          SELECT s2.id FROM scores s2
          WHERE s2.group_key = matched_groups.group_key
            AND s2.deleted_at IS NULL
          ORDER BY
            CASE
              WHEN s2.clean_title LIKE '%Full Score%' THEN 0
              WHEN s2.clean_title LIKE '%Conductor%' THEN 1
              ELSE 2
            END,
            s2.clean_title
          LIMIT 1
        )
        FROM (
          SELECT DISTINCT s.group_key
          FROM scores s
          WHERE s.id IN (#{fts_match})
            AND s.group_key IS NOT NULL
        ) matched_groups
      )
    SQL
  }

  # Build FTS5 query with AND semantics
  # "rock & roll" -> "rock" "roll" (AND match, special chars stripped)
  # "Dvořák symphony" -> "dvorak" "symphony" (accent-normalized)
  def self.build_fts5_query(query)
    return "" if query.blank?
    normalized = query.unicode_normalize(:nfkd).gsub(/\p{M}/, "").downcase
    words = normalized.split.map { |w| w.gsub(/["\(\)\*\-\+\:\^\~\&]/, "") }.reject(&:empty?)
    return "" if words.empty?
    words.map { |w| "\"#{w}\"" }.join(" ")
  end

  # Normalize text for search: strip accents, preserve case
  # "Händel" -> "Handel", "Dvořák" -> "Dvorak", "Café" -> "Cafe"
  # Used for normalizing title/composer columns and search_by_title scope
  def self.normalize_for_search(text)
    return "" if text.blank?
    text.unicode_normalize(:nfkd).gsub(/\p{M}/, "")
  end

  # Derive group_key for SMD ensemble parts
  # "Title (arr. Someone) - Trombone 2" -> "title (arr. someone)|hl-12345678"
  # "Title (arr. Someone) - Pt.3 - Viola" -> "title (arr. someone)|hl-12345678"
  # Returns nil for solo products without instrument suffix
  # Product code from thumbnail_url distinguishes different editions (jazz band vs concert band)
  #
  # Note: Bundle products like "Title (arr. Someone)" without instrument suffix get their
  # group_key set via backfill task which checks if sibling parts exist with same thumbnail.
  def self.derive_group_key(clean_title, thumbnail_url = nil)
    return nil if clean_title.blank?
    return nil unless clean_title.include?(" - ")

    before, _, after = clean_title.rpartition(" - ")
    return nil unless INSTRUMENT_PATTERNS.any? { |pattern| after.match?(pattern) }

    # Strip intermediate segments (Pt.X, Sample Solo) so all parts group together
    before = before.gsub(/ - Pt\.?\s*\d+\s*$/i, "")
    before = before.gsub(/ - Sample Solo$/i, "")

    key = before.downcase.strip

    # Append product code to distinguish different editions (jazz band vs concert band)
    if (product_code = extract_product_code(thumbnail_url))
      key = "#{key}|#{product_code}"
    end

    key
  end

  # Derive group_key for bundle products (used by backfill task)
  # Only returns a key if the bundle's thumbnail matches existing grouped parts
  def self.derive_bundle_group_key(clean_title, thumbnail_url)
    return nil if clean_title.blank? || thumbnail_url.blank?
    return nil if clean_title.include?(" - ") # Has instrument suffix, use derive_group_key instead
    return nil unless clean_title.match?(/\(arr\.[^)]+\)\s*$/i) # Must have arranger

    product_code = extract_product_code(thumbnail_url)
    return nil unless product_code

    # Check if parts with this product code exist
    potential_key = "#{clean_title.downcase.strip}|#{product_code}"
    return potential_key if where(group_key: potential_key).exists?

    nil
  end

  # Extract HL product code from SMD thumbnail URL
  # "https://img.sheetmusic.direct/catalogue/product/hl-07013386-md.jpg" -> "hl-07013386"
  def self.extract_product_code(thumbnail_url)
    return nil if thumbnail_url.blank?
    thumbnail_url[/hl-\d+/]
  end

  # Deduplicate SMD arrangements: show one card per group_key
  # Uses pre-computed is_group_representative column (set by backfill_group_keys task)
  # Ungrouped scores (group_key IS NULL) always included
  #
  # Note: For search results, deduplication happens in the search scope itself.
  # This scope is for non-search listings (browsing all scores, filtering by source, etc.)
  scope :deduplicate_arrangements, -> {
    where(group_key: nil).or(where(is_group_representative: true))
  }

  # Get all other parts in this score's arrangement group
  def grouped_parts
    return Score.none if group_key.blank?
    Score.where(group_key: group_key).where.not(id: id).order(:clean_title)
  end

  # Check if this score has other parts in its group
  def has_grouped_parts?
    group_key.present? && grouped_parts.exists?
  end

  # Total parts count including this score
  def group_parts_count
    return 1 if group_key.blank?
    Score.where(group_key: group_key).count
  end

  # Extract the instrument/part name from clean_title
  # "Birds of a Feather (arr. Roger Holmes) - Trombone 2" -> "Trombone 2"
  def part_name
    if clean_title&.include?(" - ")
      clean_title.rpartition(" - ").last
    elsif group_key.present?
      I18n.t("score.set_label", default: "Set")
    end
  end

  # Sorting scopes
  # Popularity = views only. Favorites field reserved for future Pro user favorites.
  scope :order_by_popularity, -> { order(views: :desc) }
  scope :order_by_newest, -> { order(created_at: :desc) }
  scope :order_by_title, -> { order(title: :asc) }
  scope :order_by_composer, -> { order(composer: :asc) }

  # Helper method to get first key signature (some scores have multiple)
  def primary_key_signature
    key_signature&.split(",")&.first&.strip
  end

  # Primary instrument for display on score cards
  # SMD scores have curated main_instrument; others need extraction/normalization
  def primary_instrument
    # SMD scores have curated categories - use as-is
    return main_instrument if main_instrument.present?

    # For other sources, extract from instruments field
    return nil if instruments.blank?

    normalize_instruments_for_display(instruments)
  end

  # Helper method to get first time signature
  def primary_time_signature
    time_signature&.split(",")&.first&.strip
  end

  # Effective tempo: prefer metronome mark, fall back to estimated from text
  # Use this instead of tempo_bpm directly to include estimated tempos
  def effective_tempo
    tempo_bpm || estimated_tempo_bpm
  end

  # Effective duration: prefer Python-calculated, fall back to Ruby-estimated
  # Use this instead of duration_seconds directly to include estimated durations
  def effective_duration
    duration_seconds || estimated_duration_seconds
  end

  # Helper to parse genre field (filters out NA/N/A values)
  # Before normalization: parses hyphen-delimited tags
  # After normalization: returns single-element array with clean genre
  def genre_list
    return [] if genre.blank? || genre.upcase.in?(%w[NA N/A])
    genre.include?("-") ? genre.split("-").map(&:strip).reject(&:blank?) : [genre]
  end

  # Helper to parse tags array (filters out NA/N/A values)
  def tag_list
    (tags&.split("-")&.map(&:strip) || []).reject { |t| t.blank? || t.upcase.in?(%w[NA N/A]) }
  end

  # Check if downloadable files exist
  def has_mxl?
    mxl_path.present? && mxl_path != "N/A"
  end

  def has_pdf?
    pdf_path.present? && pdf_path != "N/A"
  end

  def has_midi?
    mid_path.present? && mid_path != "N/A"
  end

  # Source helpers
  def pdmx?
    source == "pdmx"
  end

  def cpdl?
    source == "cpdl"
  end

  def imslp?
    source == "imslp"
  end

  def external?
    cpdl? || imslp?
  end

  def openscore?
    source&.start_with?("openscore")
  end

  def smd?
    source == "smd"
  end

  # Returns clean_title for SMD scores, title otherwise
  def display_title
    smd? ? (clean_title.presence || title) : title
  end

  # SMD score with valid external_id (can link to purchase)
  def smd_purchasable?
    smd? && external_id.present?
  end

  # Derived from has_vocal (set by LLM normalizer)
  def is_instrumental?
    has_vocal == false
  end

  # Vocal score with non-vocal parts (piano, orchestra, etc.)
  def has_accompaniment?
    has_vocal && instruments.present?
  end

  # For CPDL scores, return the file URL
  # Note: CPDL pdf_path already contains full URLs
  def cpdl_file_url(filename)
    return nil unless cpdl? && filename.present?
    filename
  end

  # For IMSLP scores, generate file URLs via Special:IMSLPImageHandler (requires cookie)
  def imslp_file_url(filename)
    return nil unless imslp? && filename.present? && external_id.present?
    encoded_filename = URI.encode_www_form_component(filename)
    "https://imslp.org/wiki/Special:IMSLPImageHandler/#{external_id}/#{encoded_filename}"
  end

  # Get the full PDF URL for external scores
  def pdf_url
    return nil unless has_pdf?

    case source
    when "cpdl"
      cpdl_file_url(pdf_path)
    when "imslp"
      imslp_file_url(pdf_path)
    else
      pdf_path
    end
  end

  # Get the full MusicXML URL/path
  def mxl_url
    return nil unless has_mxl?

    case source
    when "cpdl"
      cpdl_file_url(mxl_path)
    when "imslp"
      imslp_file_url(mxl_path)
    when "pdmx"
      Rails.application.config.x.pdmx_path.join(mxl_path.delete_prefix("./")).to_s
    when "openscore-lieder"
      OpenscoreImporter.root_path.join(mxl_path.delete_prefix("./")).to_s
    when "openscore-quartets"
      OpenscoreQuartetsImporter.root_path.join(mxl_path.delete_prefix("./")).to_s
    else
      mxl_path
    end
  end

  # Get the full MIDI URL for external scores
  def mid_url
    return nil unless has_midi?

    case source
    when "cpdl"
      cpdl_file_url(mid_path)
    when "imslp"
      imslp_file_url(mid_path)
    else
      mid_path
    end
  end

  # Get larger preview image URL from thumbnail URL
  # - PDMX/MuseScore: strips @WIDTHxHEIGHT suffix (score_0.png@300x420 -> score_0.png)
  # - IMSLP: uses same URL (CDN generates one size per PDF)
  def thumbnail_url_original
    return nil unless thumbnail_url.present?

    if imslp?
      # IMSLP PDF previews: same URL for all sizes (CDN-generated)
      thumbnail_url
    else
      # PDMX/MuseScore: remove @WIDTHxHEIGHT suffix
      thumbnail_url.sub(/@\d+x\d+/, "")
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Download & File Availability
  # ─────────────────────────────────────────────────────────────────

  def has_downloads?
    has_pdf? || has_midi? || has_mxl?
  end

  # Returns array of available download formats: [:pdf, :midi, :mxl]
  def available_formats
    formats = []
    formats << :pdf if has_pdf?
    formats << :midi if has_midi?
    formats << :mxl if has_mxl?
    formats
  end

  # ─────────────────────────────────────────────────────────────────
  # Metadata Presence Checks (for conditional rendering)
  # ─────────────────────────────────────────────────────────────────

  def has_music_details?
    voicing.present? ||
      key_signature.present? ||
      time_signature.present? ||
      num_parts.to_i.positive? ||
      language.present? ||
      instruments.present? ||
      page_count.to_i.positive? ||
      complexity.to_i.positive? ||
      rating.to_f.positive?
  end

  def has_about_info?
    editor.present? || license.present? || cpdl_number.present? || posted_date.present?
  end

  def has_stats?
    views.to_i.positive? || favorites.to_i.positive?
  end

  # RAG needs normalized data: instrumentation + identity
  def ready_for_rag?
    has_voicing = voicing_normalized? && voicing.present?
    has_instruments = instruments_normalized? && instruments.present?
    has_composer = composer_normalized? && composer.present? && composer != "NA"
    has_genre = genre_normalized? && genre.present?

    (has_voicing || has_instruments) && (has_composer || has_genre)
  end

  # chord_span only meaningful for solo keyboard/harp (reliable semitone measurement)
  # Not for: vocals, chamber music, guitar (fret measurement unreliable)
  def chord_span_applicable?
    return false if has_vocal
    return false if instruments.blank?
    return false if instruments.include?(",")

    instruments.downcase.match?(/piano|organ|harpsichord|clavichord|keyboard|harp/)
  end

  private

  # Ensemble keywords that should be shown as-is (not reduced to single instrument)
  ENSEMBLE_KEYWORDS = %w[orchestra orchestral band ensemble chamber].freeze

  # Known instrument names we can confidently display
  KNOWN_INSTRUMENTS = %w[
    piano organ harpsichord keyboard clavichord
    guitar lute harp mandolin banjo ukulele
    violin viola cello bass contrabass
    flute oboe clarinet bassoon recorder
    trumpet trombone horn tuba
    percussion drums timpani
    accordion harmonica
  ].freeze

  def normalize_instruments_for_display(raw_instruments)
    normalized = raw_instruments.downcase.strip

    # Check for ensemble keywords first
    ENSEMBLE_KEYWORDS.each do |keyword|
      return keyword.capitalize if normalized.include?(keyword)
    end

    # Check for "a cappella" - keep as-is
    return "A cappella" if normalized.include?("a cappella") || normalized.include?("acappella")

    # Split by common delimiters
    parts = raw_instruments.split(/[,;]/).map(&:strip).reject(&:blank?)

    # Check for voice part codes (SATB, SSA, SS, etc.) - only S, A, T, B letters
    first_part_clean = parts.first&.downcase&.gsub(/\s+/, "")
    if first_part_clean&.match?(/\A[satb]+\z/)
      # 3+ voice parts = Choir, 2 = Vocal (duet), 1 = skip
      return "Choir" if first_part_clean.length >= 3
      return "Vocal" if first_part_clean.length == 2
    end

    # Check for "Solo S", "Solo A", etc. (solo voice)
    if parts.first&.match?(/^solo\s+[satb]/i)
      # If accompanied, show "Voice & [accompaniment]"
      if parts.size > 1 && parts[1]&.match?(/piano|organ|keyboard/i)
        return "Voice & Piano"
      end
      return "Voice"
    end

    # If 3+ distinct instruments, it's an ensemble
    if parts.size >= 3
      return "Ensemble"
    end

    # For voice + accompaniment combinations (2 parts)
    if parts.size == 2
      voice_part = parts.find { |p| p.match?(/voice|vocal|singer|soprano|alto|tenor|bass|baritone/i) }
      if voice_part
        other_part = (parts - [voice_part]).first
        accompaniment = case other_part&.downcase
        when /piano|keyboard/ then "Piano"
        when /organ/ then "Organ"
        when /guitar/ then "Guitar"
        when /lute/ then "Lute"
        when /harp/ then "Harp"
        else nil
        end
        return "Voice & #{accompaniment}" if accompaniment
      end
    end

    # Only return known instrument names, otherwise nil (no badge)
    first_part = parts.first&.downcase
    return nil if first_part.blank?

    # Check for exact match or word boundary match (e.g., "piano 4-hands" matches "piano")
    KNOWN_INSTRUMENTS.each do |instrument|
      if first_part == instrument || first_part.match?(/\b#{instrument}\b/)
        return instrument.capitalize
      end
    end

    # Unknown pattern - don't show badge
    nil
  end

  def update_normalized_search_columns
    self.title_normalized = self.class.normalize_for_search(title)
    self.composer_normalized = self.class.normalize_for_search(composer)
  end

  def instrument_context_changed?
    saved_change_to_instruments? || saved_change_to_has_vocal?
  end

  def apply_extraction_context!
    return if chord_span_applicable? || max_chord_span.nil?
    update_columns(max_chord_span: nil)
  end

  def enforce_chord_span_applicability
    self.max_chord_span = nil unless chord_span_applicable?
  end
end
