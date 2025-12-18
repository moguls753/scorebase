# frozen_string_literal: true

# Handles gallery page generation for scores.
# PDF pages are rendered to WebP images stored in Active Storage (R2).
module Score::Galleried
  extend ActiveSupport::Concern

  included do
    has_many :score_pages, dependent: :destroy

    # Scores with PDFs that don't have any gallery pages yet
    scope :needing_gallery, -> {
      where.not(pdf_path: [nil, "", "N/A"])
           .left_joins(:score_pages)
           .where(score_pages: { id: nil })
    }
  end

  def generate_gallery
    GalleryGenerator.new(self).generate
  end

  def regenerate_gallery
    score_pages.destroy_all
    generate_gallery
  end

  def has_gallery?
    score_pages.exists?
  end

  def gallery_pages
    score_pages.ordered.includes(image_attachment: :blob)
  end
end
