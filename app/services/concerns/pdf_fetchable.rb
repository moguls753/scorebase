# frozen_string_literal: true

# Shared PDF fetching logic for services that need to work with PDF files
# Handles three sources in priority order: R2 storage, local disk (PDMX), external URL
module PdfFetchable
  extend ActiveSupport::Concern

  included do
    include HttpDownloadable
  end

  # Fetches PDF to temp directory from R2, local disk, or external URL
  # Returns path to downloaded PDF or nil on failure
  def fetch_pdf_to(tmpdir)
    dest_path = File.join(tmpdir, "source.pdf")

    # 1. R2-synced PDF (IMSLP/CPDL)
    if score.pdf_file.attached?
      File.binwrite(dest_path, score.pdf_file.download)
      return dest_path
    end

    # 2. Local disk (PDMX)
    if score.pdmx? && score.pdf_path.present?
      local_path = Rails.application.config.x.pdmx_path.join(score.pdf_path.delete_prefix("./")).to_s
      if File.exist?(local_path)
        FileUtils.cp(local_path, dest_path)
        return dest_path
      end
    end

    # 3. External URL (not yet synced)
    if score.external? && score.pdf_url.present?
      http_download(score.pdf_url, dest_path, timeout: 120)
      return dest_path
    end

    nil
  rescue HttpDownloadable::DownloadError => e
    log_error(e) if respond_to?(:log_error, true)
    nil
  rescue StandardError => e
    log_error(e) if respond_to?(:log_error, true)
    nil
  end
end
