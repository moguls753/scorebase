# frozen_string_literal: true

# Handles thumbnail generation for scores.
# Thumbnails are cached to Active Storage (R2) from external URLs or PDF first pages.
module Score::Thumbnailable
  extend ActiveSupport::Concern

  included do
    has_one_attached :thumbnail_image

    # Scores that can have thumbnails generated (from URL or PDF) but don't have one yet.
    # Excludes commercial partners — they serve thumbnails from their own CDN, and
    # copying publisher cover art into our bucket is a different copyright situation.
    scope :needing_thumbnail, -> {
      left_joins(:thumbnail_image_attachment)
        .where(active_storage_attachments: { id: nil })
        .where.not(source: Score::COMMERCIAL_SOURCES)
        .where("thumbnail_url IS NOT NULL AND thumbnail_url != '' OR pdf_path IS NOT NULL AND pdf_path != ''")
    }
  end

  def generate_thumbnail
    ThumbnailGenerator.new(self).generate
  end

  # Partner cover art is hotlinked, never copied: it would put publisher artwork in
  # our own bucket, which is bandwidth, cost and a different copyright question.
  # Shopify's CDN resizes on request, so ask for the size actually being rendered
  # instead of shipping the full image.
  CDN_RESIZE_HOSTS = %w[cdn.shopify.com].freeze

  def thumbnail(width: nil)
    return thumbnail_image.url if thumbnail_image.attached?
    # SMD: prefer preview_image_url (actual sheet music) over thumbnail_url (CD cover)
    url = preview_image_url.presence || thumbnail_url.presence
    return nil if url.nil?

    width ? with_cdn_width(url, width) : url
  end

  def has_thumbnail?
    thumbnail_image.attached? || preview_image_url.present? || thumbnail_url.present?
  end

  private

  def with_cdn_width(url, width)
    uri = URI.parse(url)
    return url unless CDN_RESIZE_HOSTS.include?(uri.host)

    uri.query = [ uri.query, "width=#{width.to_i}" ].compact.join("&")
    uri.to_s
  rescue URI::InvalidURIError
    url
  end
end
