# Syncs PDFs from IMSLP/CPDL to Active Storage (R2)
class PdfSyncer
  include HttpDownloadable

  attr_reader :score, :errors

  def initialize(score)
    @score = score
    @errors = []
  end

  def sync
    return true if score.pdf_file.attached?
    return true if score.pdmx?  # PDMX already has local PDFs

    unless score.has_pdf? && score.external?
      @errors << "No external PDF available"
      return false
    end

    download_and_attach
  rescue HttpDownloadable::DownloadError, StandardError => e
    log_error(e)
    false
  end

  private

  def download_and_attach
    Dir.mktmpdir("pdf") do |tmpdir|
      pdf_path = File.join(tmpdir, "download.pdf")
      response = http_download(score.pdf_url, pdf_path, timeout: 120)
      filename = extract_filename(response, score.pdf_url)
      attach_pdf(pdf_path, filename)
    end
    true
  end

  def extract_filename(response, url)
    # Try Content-Disposition header first
    if response["content-disposition"]
      match = response["content-disposition"].match(/filename="?([^";\n]+)"?/)
      return match[1] if match
    end

    # Fall back to URL path
    path = URI(url).path
    filename = File.basename(path)
    filename = URI.decode_www_form_component(filename) if filename.include?("%")

    filename.presence || "#{score.id}.pdf"
  end

  def attach_pdf(pdf_path, filename)
    score.pdf_file.attach(
      io: File.open(pdf_path),
      filename: filename,
      content_type: "application/pdf"
    )
  end

  def log_error(error)
    @errors << error.message
    Rails.logger.error("[PdfSyncer] Score ##{score.id}: #{error.message}")
  end
end
