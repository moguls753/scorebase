# Generates WebP thumbnails from external thumbnail URLs and stores in Active Storage (R2)
class ThumbnailGenerator
  include HttpDownloadable

  THUMBNAIL_SIZE = 280  # Matches card max-width
  WEBP_QUALITY = 75     # Good balance of quality/size (~5-10KB per image)

  attr_reader :score, :errors

  def initialize(score)
    @score = score
    @errors = []
  end

  def generate
    return true if score.thumbnail_image.attached?

    unless score.thumbnail_url.present?
      @errors << "No thumbnail_url available"
      return false
    end

    cache_thumbnail
  rescue HttpDownloadable::DownloadError, StandardError => e
    log_error(e)
    false
  end

  private

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
end
