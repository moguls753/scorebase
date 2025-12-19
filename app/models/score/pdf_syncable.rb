# frozen_string_literal: true

# Handles PDF syncing for external scores (IMSLP/CPDL).
# PDFs are downloaded and stored in Active Storage (R2) for reliable serving.
module Score::PdfSyncable
  extend ActiveSupport::Concern

  included do
    # External scores with PDFs that aren't synced to R2 yet
    # Excludes PDMX (local disk) since those don't need syncing
    scope :needing_pdf_sync, -> {
      where(source: %w[imslp cpdl])
           .where.not(pdf_path: [nil, "", "N/A"])
           .left_joins(:pdf_file_attachment)
           .where(active_storage_attachments: { id: nil })
    }
  end

  def sync_pdf
    PdfSyncer.new(self).sync
  end

  def pdf_synced?
    pdf_file.attached?
  end
end
