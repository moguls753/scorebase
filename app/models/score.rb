# == Schema Information
#
# Table name: scores
#
#  id                   :integer          not null, primary key
#  complexity           :integer
#  composer             :string
#  cpdl_number          :string
#  data_path            :string
#  description          :text
#  editor               :string
#  external_url         :string
#  favorites            :integer          default(0)
#  genres               :text
#  instruments          :string
#  key_signature        :string
#  language             :string
#  license              :string
#  lyrics               :text
#  metadata_path        :string
#  mid_path             :string
#  mxl_path             :string
#  normalization_status :string           default("pending"), not null
#  num_parts            :integer
#  page_count           :integer
#  pdf_path             :string
#  posted_date          :date
#  rating               :decimal(3, 2)
#  source               :string           default("pdmx")
#  tags                 :text
#  thumbnail_url        :string
#  time_signature       :string
#  title                :string
#  views                :integer          default(0)
#  voicing              :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  external_id          :string
#
# Indexes
#
#  index_scores_on_complexity            (complexity)
#  index_scores_on_composer              (composer)
#  index_scores_on_external_id           (external_id)
#  index_scores_on_genres                (genres)
#  index_scores_on_instruments           (instruments)
#  index_scores_on_key_signature         (key_signature)
#  index_scores_on_normalization_status  (normalization_status)
#  index_scores_on_num_parts             (num_parts)
#  index_scores_on_rating                (rating)
#  index_scores_on_source                (source)
#  index_scores_on_time_signature        (time_signature)
#  index_scores_on_views                 (views)
#  index_scores_on_voicing               (voicing)
#
class Score < ApplicationRecord
  # Sources
  SOURCES = %w[pdmx cpdl imslp].freeze

  # Active Storage attachments
  has_one_attached :thumbnail_image
  has_one_attached :preview_image
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

  # Composer normalization status
  enum :normalization_status, {
    pending: "pending",
    normalized: "normalized",
    failed: "failed"
  }, default: :pending

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

  # Get the full MusicXML URL for external scores
  def mxl_url
    return nil unless has_mxl?

    case source
    when "cpdl"
      cpdl_file_url(mxl_path)
    when "imslp"
      imslp_file_url(mxl_path)
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

  # Unified thumbnail accessor - prefers cached local thumbnail over external URL
  def thumbnail
    return thumbnail_image if thumbnail_image.attached?
    return thumbnail_url if thumbnail_url.present?
    nil
  end

  # Unified preview accessor - returns original external URL or attached image
  def preview
    return thumbnail_url_original if thumbnail_url.present?
    return preview_image if preview_image.attached?
    nil
  end

  def has_thumbnail?
    thumbnail_url.present? || thumbnail_image.attached?
  end

  def has_preview?
    thumbnail_url.present? || preview_image.attached?
  end
end
