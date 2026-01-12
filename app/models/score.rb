# == Schema Information
#
# Table name: scores
#
#  id                         :integer          not null, primary key
#  accidental_count           :integer
#  ambitus_semitones          :integer
#  arpeggio_mark_count        :integer
#  avg_chord_span             :float
#  beat_count                 :integer
#  cadence_types              :text
#  chord_count                :integer
#  chromatic_note_count       :integer
#  chromatic_ratio            :float
#  clefs_used                 :text
#  complexity                 :integer
#  composer                   :string
#  composer_status            :string           default("pending"), not null
#  computed_difficulty        :integer
#  contrary_motion_ratio      :float
#  cpdl_number                :string
#  data_path                  :string
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
#  is_instrumental            :boolean
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
#  pitch_range_per_part       :json
#  posted_date                :date
#  predominant_rhythm         :string
#  rag_status                 :string           default("pending"), not null
#  rating                     :decimal(3, 2)
#  repeats_count              :integer
#  rhythm_distribution        :json
#  rhythmic_variety           :float
#  search_text                :text
#  search_text_generated_at   :datetime
#  sections_count             :integer
#  simultaneous_note_avg      :float
#  slur_count                 :integer
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
#  index_scores_on_ambitus_semitones             (ambitus_semitones)
#  index_scores_on_chromatic_ratio               (chromatic_ratio)
#  index_scores_on_complexity                    (complexity)
#  index_scores_on_composer                      (composer)
#  index_scores_on_composer_status               (composer_status)
#  index_scores_on_computed_difficulty           (computed_difficulty)
#  index_scores_on_duration_seconds              (duration_seconds)
#  index_scores_on_event_count                   (event_count)
#  index_scores_on_external_id                   (external_id)
#  index_scores_on_extraction_status             (extraction_status)
#  index_scores_on_genre                         (genre)
#  index_scores_on_genre_status                  (genre_status)
#  index_scores_on_genre_status_and_lower_genre  (genre_status, LOWER(genre))
#  index_scores_on_grade_status                  (grade_status)
#  index_scores_on_has_extracted_lyrics          (has_extracted_lyrics)
#  index_scores_on_has_vocal                     (has_vocal)
#  index_scores_on_has_vocal_status              (has_vocal_status)
#  index_scores_on_highest_pitch                 (highest_pitch)
#  index_scores_on_indexed_at                    (indexed_at)
#  index_scores_on_instruments                   (instruments)
#  index_scores_on_instruments_status            (instruments_status)
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
#  index_scores_on_rag_status                    (rag_status)
#  index_scores_on_rating                        (rating)
#  index_scores_on_source                        (source)
#  index_scores_on_tempo_bpm                     (tempo_bpm)
#  index_scores_on_texture_type                  (texture_type)
#  index_scores_on_time_signature                (time_signature)
#  index_scores_on_views                         (views)
#  index_scores_on_voicing                       (voicing)
#  index_scores_on_voicing_status                (voicing_status)
#
class Score < ApplicationRecord
  include Thumbnailable
  include Galleried
  include PdfSyncable

  # Sources
  SOURCES = %w[pdmx cpdl imslp openscore-lieder openscore-quartets].freeze

  # Active Storage attachments
  has_one_attached :pdf_file

  # Validations
  validates :title, presence: true
  validates :data_path, presence: true, uniqueness: true
  validates :source, inclusion: { in: SOURCES }, allow_nil: true

  # Keep normalized search columns in sync
  before_save :update_normalized_search_columns, if: -> { title_changed? || composer_changed? }

  # Pagination
  paginates_per 12

  # Source scopes
  scope :from_pdmx, -> { where(source: "pdmx") }
  scope :from_cpdl, -> { where(source: "cpdl") }
  scope :from_imslp, -> { where(source: "imslp") }
  scope :by_source, ->(source) { where(source: source) if source.present? }

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
  scope :by_complexity, ->(complexity) { where(complexity: complexity) if complexity.present? }
  scope :by_num_parts, ->(parts) { where(num_parts: parts) if parts.present? }

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

  # Instrument filter for hub pages
  scope :by_instrument, ->(instrument_name) {
    return all if instrument_name.blank?
    where("LOWER(instruments) LIKE ?", "%#{sanitize_sql_like(instrument_name.downcase)}%")
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
  scope :search, ->(query) {
    return all if query.blank?

    normalized = normalize_for_search(query)

    where(
      "title_normalized LIKE :q OR composer_normalized LIKE :q OR genre LIKE :q",
      q: "%#{sanitize_sql_like(normalized)}%"
    )
  }

  # Normalize text for search: strip accents, preserve case
  # "Händel" -> "Handel", "Dvořák" -> "Dvorak", "Café" -> "Cafe"
  def self.normalize_for_search(text)
    return "" if text.blank?
    text.unicode_normalize(:nfkd).gsub(/\p{M}/, "")
  end

  # Sorting scopes
  scope :order_by_popularity, -> { order(views: :desc, favorites: :desc) }
  scope :order_by_rating, -> { order(rating: :desc, views: :desc) }
  scope :order_by_newest, -> { order(created_at: :desc) }
  scope :order_by_title, -> { order(title: :asc) }
  scope :order_by_composer, -> { order(composer: :asc) }

  # Helper method to get first key signature (some scores have multiple)
  def primary_key_signature
    key_signature&.split(",")&.first&.strip
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

  private

  def update_normalized_search_columns
    self.title_normalized = self.class.normalize_for_search(title)
    self.composer_normalized = self.class.normalize_for_search(composer)
  end

  # chord_span only meaningful for solo keyboard/harp (reliable semitone measurement)
  # Not for: vocals, chamber music, guitar (fret measurement unreliable)
  def chord_span_applicable?
    return false if has_vocal
    return false if instruments.blank?
    return false if instruments.include?(',')

    instruments.downcase.match?(/piano|organ|harpsichord|clavichord|keyboard|harp/)
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
