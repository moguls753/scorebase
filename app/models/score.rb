# == Schema Information
#
# Table name: scores
#
#  id                       :integer          not null, primary key
#  accidental_count         :integer
#  ambitus_semitones        :integer
#  cadence_types            :text
#  chord_symbols            :json
#  chromatic_complexity     :float
#  clefs_used               :text
#  complexity               :integer
#  composer                 :string
#  cpdl_number              :string
#  data_path                :string
#  description              :text
#  detected_instruments     :text
#  duration_seconds         :float
#  dynamic_range            :string
#  editor                   :string
#  expression_markings      :text
#  external_url             :string
#  extracted_at             :datetime
#  extracted_lyrics         :text
#  extraction_error         :text
#  extraction_status        :string           default("pending"), not null
#  favorites                :integer          default(0)
#  final_cadence            :string
#  form_analysis            :string
#  genres                   :text
#  harmonic_rhythm          :float
#  has_accompaniment        :boolean
#  has_articulations        :boolean
#  has_dynamics             :boolean
#  has_extracted_lyrics     :boolean
#  has_fermatas             :boolean
#  has_ornaments            :boolean
#  has_tempo_changes        :boolean
#  highest_pitch            :string
#  index_version            :integer
#  indexed_at               :datetime
#  instrument_families      :text
#  instruments              :string
#  interval_distribution    :json
#  is_instrumental          :boolean
#  is_vocal                 :boolean
#  key_confidence           :float
#  key_correlations         :json
#  key_signature            :string
#  language                 :string
#  largest_interval         :integer
#  license                  :string
#  lowest_pitch             :string
#  lyrics                   :text
#  lyrics_language          :string
#  measure_count            :integer
#  melodic_complexity       :float
#  melodic_contour          :string
#  metadata_path            :string
#  mid_path                 :string
#  modulation_count         :integer
#  modulations              :text
#  music21_version          :string
#  musicxml_source          :string
#  mxl_path                 :string
#  normalization_status     :string           default("pending"), not null
#  normalized_genre         :string
#  note_count               :integer
#  note_density             :float
#  num_parts                :integer
#  page_count               :integer
#  part_names               :text
#  pdf_path                 :string
#  period                   :string
#  period_source            :string
#  pitch_range_per_part     :json
#  polyphonic_density       :float
#  posted_date              :date
#  predominant_rhythm       :string
#  rag_status               :string           default("pending"), not null
#  rating                   :decimal(3, 2)
#  repeats_count            :integer
#  rhythm_distribution      :json
#  rhythmic_variety         :float
#  search_text              :text
#  search_text_generated_at :datetime
#  sections_count           :integer
#  source                   :string           default("pdmx")
#  stepwise_motion_ratio    :float
#  syllable_count           :integer
#  syncopation_level        :float
#  tags                     :text
#  tempo_bpm                :integer
#  tempo_marking            :string
#  texture_type             :string
#  thumbnail_url            :string
#  time_signature           :string
#  title                    :string
#  unique_pitches           :integer
#  views                    :integer          default(0)
#  voice_independence       :float
#  voice_ranges             :json
#  voicing                  :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  external_id              :string
#
# Indexes
#
#  index_scores_on_ambitus_semitones     (ambitus_semitones)
#  index_scores_on_chromatic_complexity  (chromatic_complexity)
#  index_scores_on_complexity            (complexity)
#  index_scores_on_composer              (composer)
#  index_scores_on_duration_seconds      (duration_seconds)
#  index_scores_on_external_id           (external_id)
#  index_scores_on_extraction_status     (extraction_status)
#  index_scores_on_genres                (genres)
#  index_scores_on_has_extracted_lyrics  (has_extracted_lyrics)
#  index_scores_on_highest_pitch         (highest_pitch)
#  index_scores_on_indexed_at            (indexed_at)
#  index_scores_on_instruments           (instruments)
#  index_scores_on_is_vocal              (is_vocal)
#  index_scores_on_key_confidence        (key_confidence)
#  index_scores_on_key_signature         (key_signature)
#  index_scores_on_lowest_pitch          (lowest_pitch)
#  index_scores_on_measure_count         (measure_count)
#  index_scores_on_melodic_complexity    (melodic_complexity)
#  index_scores_on_modulation_count      (modulation_count)
#  index_scores_on_normalization_status  (normalization_status)
#  index_scores_on_note_count            (note_count)
#  index_scores_on_num_parts             (num_parts)
#  index_scores_on_period                (period)
#  index_scores_on_rag_status            (rag_status)
#  index_scores_on_rating                (rating)
#  index_scores_on_source                (source)
#  index_scores_on_tempo_bpm             (tempo_bpm)
#  index_scores_on_texture_type          (texture_type)
#  index_scores_on_time_signature        (time_signature)
#  index_scores_on_views                 (views)
#  index_scores_on_voicing               (voicing)
#
class Score < ApplicationRecord
  include Thumbnailable
  include Galleried
  include PdfSyncable

  # Sources
  SOURCES = %w[pdmx cpdl imslp].freeze

  # Active Storage attachments
  has_one_attached :pdf_file

  # Validations
  validates :title, presence: true
  validates :data_path, presence: true, uniqueness: true
  validates :source, inclusion: { in: SOURCES }, allow_nil: true

  # Pagination
  paginates_per 12

  # Source scopes
  scope :from_pdmx, -> { where(source: "pdmx") }
  scope :from_cpdl, -> { where(source: "cpdl") }
  scope :from_imslp, -> { where(source: "imslp") }
  scope :by_source, ->(source) { where(source: source) if source.present? }

  enum :normalization_status, {
    pending: "pending",
    normalized: "normalized",
    failed: "failed"
  }, default: :pending, prefix: :normalization

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

  # Filter out corrupted encoding (mojibake) that breaks AI JSON generation
  scope :safe_for_ai, -> {
    where.not("composer LIKE ?", "%Ð%Ð%")         # Cyrillic mojibake
         .where.not("composer LIKE ?", "%ààà%")   # Corrupted Thai
         .where.not("composer LIKE ?", "%ä%ä%")   # Double-encoded CJK
         .where.not("composer LIKE ?", "%å%å%")   # Double-encoded CJK
         .where.not("composer LIKE ?", "%ã%ã%")   # Double-encoded Japanese
         .where.not("composer LIKE ?", "%Å%")     # Double-encoded European
         .where.not("composer LIKE ?", "%Î%Î%")   # Corrupted Greek
  }

  # Scopes for filtering
  scope :by_key_signature, ->(key) { where(key_signature: key) if key.present? }
  scope :by_time_signature, ->(time) { where(time_signature: time) if time.present? }
  scope :by_complexity, ->(complexity) { where(complexity: complexity) if complexity.present? }
  scope :by_num_parts, ->(parts) { where(num_parts: parts) if parts.present? }

  # Genre filter (genres stored as comma-separated text)
  # Special handling for "Sacred" to match both "Sacred" and "religiousmusic"
  scope :by_genre, ->(genre) {
    return all if genre.blank?

    if genre.downcase == "sacred"
      where("genres LIKE ? OR genres LIKE ?", "%Sacred%", "%religiousmusic%")
    else
      where("genres LIKE ?", "%#{sanitize_sql_like(genre)}%")
    end
  }

  # Period filter (historical period from genre tags) - case-insensitive for UI filters
  scope :by_period, ->(period) {
    return all if period.blank?

    case period.downcase
    when "medieval"
      where("genres LIKE ?", "%Medieval%")
    when "renaissance"
      where("genres LIKE ?", "%Renaissance music%")
    when "baroque"
      where("genres LIKE ?", "%Baroque music%")
    when "classical"
      where("genres LIKE ?", "%Classical music%")
    when "romantic"
      where("genres LIKE ?", "%Romantic music%")
    when "modern"
      where("genres LIKE ? OR genres LIKE ?", "%Modern music%", "%20th century%")
    else
      all
    end
  }

  # Period filter with case-sensitive matching (GLOB) for hub pages.
  # Distinguishes "Classical" period from "classical" PDMX pop tag.
  scope :by_period_strict, ->(period_name) {
    variants = HubDataBuilder::PERIODS[period_name]
    return none unless variants

    conditions = variants.map { "genres GLOB ?" }.join(" OR ")
    values = variants.map { |v| "*#{v}*" }
    where(conditions, *values)
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

  # Search scope (simple SQLite LIKE search with accent normalization)
  scope :search, ->(query) {
    return all if query.blank?

    # Normalize query: "Händel" -> "Handel", "Dvořák" -> "Dvorak"
    normalized = normalize_for_search(query)

    where(
      "title LIKE :q OR composer LIKE :q OR genres LIKE :q",
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

  # Helper to parse genres array (filters out NA/N/A values)
  def genre_list
    (genres&.split("-")&.map(&:strip) || []).reject { |g| g.blank? || g.upcase.in?(%w[NA N/A]) }
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

  # For CPDL scores, generate direct file URLs
  def cpdl_file_url(filename)
    return nil unless cpdl? && filename.present?
    "https://www.cpdl.org/wiki/images/#{filename}"
  end

  # For IMSLP scores, generate file URLs via Special:ImagefromIndex
  def imslp_file_url(filename)
    return nil unless imslp? && filename.present? && external_id.present?
    encoded_filename = URI.encode_www_form_component(filename)
    "https://imslp.org/wiki/Special:ImagefromIndex/#{external_id}/#{encoded_filename}"
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

  # ─────────────────────────────────────────────────────────────────
  # RAG Pipeline Readiness
  # ─────────────────────────────────────────────────────────────────

  # Check if this record has encoding issues (mojibake)
  def safe_for_ai?
    return false if composer.blank?
    # Cyrillic mojibake, corrupted Thai, double-encoded CJK/Japanese/European, corrupted Greek
    !composer.match?(/Ð.*Ð|ààà|ä.*ä|å.*å|ã.*ã|Å|Î.*Î/)
  end

  # Check if score is ready for RAG search_text generation
  def ready_for_rag?
    return false unless safe_for_ai?
    return false if title.blank?
    return false if composer.blank?
    return false unless normalization_normalized?

    # At least some musical context
    has_musical_context = [
      voicing.present?,
      normalized_genre.present?,
      period.present?,
      key_signature.present?
    ].count(true) >= 2

    has_musical_context
  end
end
