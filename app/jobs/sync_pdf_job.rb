# frozen_string_literal: true

# Syncs a single PDF from external source (IMSLP/CPDL) to Active Storage (R2).
# Delegates to Score#sync_pdf (from PdfSyncable concern).
class SyncPdfJob < ApplicationJob
  queue_as :pdfs

  # PDF downloads can be slow, use longer retry delays
  retry_on StandardError, wait: 2.minutes, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(score_id)
    Score.find(score_id).sync_pdf
  end
end
