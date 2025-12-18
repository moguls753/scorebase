# frozen_string_literal: true

# Handles thumbnail generation for scores.
# Thumbnails are cached to Active Storage (R2) from external URLs or PDF first pages.
module Score::Thumbnailable
  extend ActiveSupport::Concern

  included do
    has_one_attached :thumbnail_image

    scope :needing_thumbnail, -> {
      where.not(thumbnail_url: [nil, ""])
           .left_joins(:thumbnail_image_attachment)
           .where(active_storage_attachments: { id: nil })
    }
  end

  def generate_thumbnail
    ThumbnailGenerator.new(self).generate
  end

  def thumbnail
    return thumbnail_image.url if thumbnail_image.attached?
    return thumbnail_url if thumbnail_url.present?
    nil
  end

  def has_thumbnail?
    thumbnail_url.present? || thumbnail_image.attached?
  end
end
