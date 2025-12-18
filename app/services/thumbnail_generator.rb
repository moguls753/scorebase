# Generates WebP thumbnails from external thumbnail URLs and stores in Active Storage (R2)
# Falls back to PDF first page if thumbnail URL is unavailable or broken
class ThumbnailGenerator
  include PdfFetchable

  THUMBNAIL_SIZE = 280  # Matches card max-width
  WEBP_QUALITY = 75     # Good balance of quality/size (~5-10KB per image)

  attr_reader :score, :errors

  def initialize(score)
    @score = score
    @errors = []
  end

  def generate
    return true if score.thumbnail_image.attached?

    # Try thumbnail URL first
    if score.thumbnail_url.present?
      return true if cache_thumbnail_from_url
    end

    # Fallback to PDF first page
    if score.has_pdf?
      return true if cache_thumbnail_from_pdf
    end

    @errors << "No thumbnail source available" if @errors.empty?
    false
  end

  private

  def cache_thumbnail_from_url
    cache_thumbnail
  rescue HttpDownloadable::DownloadError => e
    log_error(e)
    clear_broken_url if e.message.include?("404")
    false
  rescue StandardError => e
    log_error(e)
    false
  end

  def cache_thumbnail_from_pdf
    Dir.mktmpdir("thumb_pdf") do |tmpdir|
      pdf_path = fetch_pdf_to(tmpdir)
      return false unless pdf_path

      webp_path = File.join(tmpdir, "thumb.webp")
      convert_pdf_to_webp(pdf_path, webp_path)
      attach_thumbnail(webp_path)
    end
    true
  rescue StandardError => e
    log_error(e)
    false
  end

  def cache_thumbnail
    Dir.mktmpdir("thumb") do |tmpdir|
      src_path = File.join(tmpdir, "source")
      webp_path = File.join(tmpdir, "thumb.webp")

      http_download(score.thumbnail_url, src_path, timeout: 30)
      convert_to_webp(src_path, webp_path)
      attach_thumbnail(webp_path)
    end
    true
  end

  def convert_to_webp(source_path, output_path)
    success = system(
      "convert", source_path,
      "-resize", "#{THUMBNAIL_SIZE}x>",
      "-quality", WEBP_QUALITY.to_s,
      output_path,
      [:out, :err] => File::NULL
    )

    raise "ImageMagick convert failed" unless success && File.exist?(output_path)
  end

  def attach_thumbnail(webp_path)
    score.thumbnail_image.attach(
      io: File.open(webp_path),
      filename: "#{score.id}.webp",
      content_type: "image/webp"
    )
  end

  def log_error(error)
    @errors << error.message
    Rails.logger.error("[ThumbnailGenerator] Score ##{score.id}: #{error.message}")
  end

  def clear_broken_url
    score.update_column(:thumbnail_url, nil)
    Rails.logger.info("[ThumbnailGenerator] Cleared broken thumbnail_url for Score ##{score.id}")
  end

  def convert_pdf_to_webp(pdf_path, output_path)
    success = system(
      "convert", "#{pdf_path}[0]",  # [0] = first page only
      "-resize", "#{THUMBNAIL_SIZE}x>",
      "-quality", WEBP_QUALITY.to_s,
      "-background", "white",
      "-flatten",
      output_path,
      [:out, :err] => File::NULL
    )

    raise "PDF to WebP conversion failed" unless success && File.exist?(output_path)
  end
end
