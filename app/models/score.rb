class Score < ApplicationRecord
  # Validations
  validates :title, presence: true
  validates :data_path, presence: true, uniqueness: true

  # Pagination
  paginates_per 12

  # Scopes for filtering
  scope :by_key_signature, ->(key) { where(key_signature: key) if key.present? }
  scope :by_time_signature, ->(time) { where(time_signature: time) if time.present? }
  scope :by_complexity, ->(complexity) { where(complexity: complexity) if complexity.present? }
  scope :by_num_parts, ->(parts) { where(num_parts: parts) if parts.present? }

  # Genre filter (genres stored as comma-separated text)
  scope :by_genre, ->(genre) { where("genres LIKE ?", "%#{sanitize_sql_like(genre)}%") if genre.present? }

  # Voicing filters (maps UI labels to num_parts)
  scope :solo, -> { where(num_parts: 1) }
  scope :duet, -> { where(num_parts: 2) }
  scope :trio, -> { where(num_parts: 3) }
  scope :quartet, -> { where(num_parts: 4) }
  scope :ensemble, -> { where("num_parts >= ?", 5) }

  # Search scope (simple SQLite LIKE search)
  scope :search, ->(query) {
    return all if query.blank?

    where(
      "title LIKE :q OR composer LIKE :q OR genres LIKE :q OR tags LIKE :q",
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

  # Helper to parse genres array
  def genre_list
    genres&.split("-")&.map(&:strip) || []
  end

  # Helper to parse tags array
  def tag_list
    tags&.split("-")&.map(&:strip) || []
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
end
