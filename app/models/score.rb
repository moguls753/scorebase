class Score < ApplicationRecord
  # Sources
  SOURCES = %w[pdmx cpdl imslp].freeze

  # Active Storage attachments
  has_one_attached :thumbnail_image
  has_one_attached :preview_image

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

  # Scopes for filtering
  scope :by_key_signature, ->(key) { where(key_signature: key) if key.present? }
  scope :by_time_signature, ->(time) { where(time_signature: time) if time.present? }
  scope :by_complexity, ->(complexity) { where(complexity: complexity) if complexity.present? }
  scope :by_num_parts, ->(parts) { where(num_parts: parts) if parts.present? }

  # Genre filter (genres stored as comma-separated text)
  scope :by_genre, ->(genre) { where("genres LIKE ?", "%#{sanitize_sql_like(genre)}%") if genre.present? }

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

  # Search scope (simple SQLite LIKE search)
  scope :search, ->(query) {
    return all if query.blank?

    where(
      "title LIKE :q OR composer LIKE :q OR genres LIKE :q",
      q: "%#{sanitize_sql_like(query)}%"
    )
  }

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

  # Get original (full-size) thumbnail URL for MuseScore thumbnails
  # Converts medium URL (score_0.png@300x420) to original (score_0.png)
  def thumbnail_url_original
    return nil unless thumbnail_url.present?
    # Remove the @WIDTHxHEIGHT suffix to get original size
    thumbnail_url.sub(/@\d+x\d+/, "")
  end

  # Unified thumbnail accessor - returns external URL or attached image
  def thumbnail
    return thumbnail_url if thumbnail_url.present?
    return thumbnail_image if thumbnail_image.attached?
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
