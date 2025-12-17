require "net/http"
require "uri"
require "tempfile"

class ThumbnailGenerator
  THUMBNAIL_SIZE = 280  # Matches card max-width
  WEBP_QUALITY = 75     # Good balance of quality/size (~10-15KB per image)

  attr_reader :score, :errors

  def initialize(score)
    @score = score
    @errors = []
  end

  # Generate cached thumbnail from external thumbnail_url
  # Returns true on success, false on failure
  def generate
    return true if score.thumbnail_image.attached?

    unless score.thumbnail_url.present?
      @errors << "No thumbnail_url available"
      return false
    end

    cache_thumbnail
  rescue => e
    log_error(e)
    false
  end

  private

  def cache_thumbnail
    Dir.mktmpdir("thumb_cache") do |tmpdir|
      src_path = File.join(tmpdir, "source")
      webp_path = File.join(tmpdir, "thumb.webp")

      download_image(score.thumbnail_url, src_path)
      convert_to_webp(src_path, webp_path)
      attach_thumbnail(webp_path)
    end
    true
  end

  def download_image(url, destination, redirect_limit: 5)
    raise "Too many redirects" if redirect_limit == 0

    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = 10
    http.read_timeout = 30

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "ScorebaseBot/1.0"

    response = http.request(request)

    case response
    when Net::HTTPSuccess
      File.binwrite(destination, response.body)
    when Net::HTTPRedirection
      redirect_url = response["location"]
      redirect_url = URI.join(url, redirect_url).to_s unless redirect_url.start_with?("http")
      download_image(redirect_url, destination, redirect_limit: redirect_limit - 1)
    else
      raise "Download failed: #{response.code} #{response.message}"
    end
  end

  def convert_to_webp(source_path, output_path)
    # Resize to THUMBNAIL_SIZE width, maintain aspect ratio, convert to WebP
    result = system(
      "convert",
      source_path,
      "-resize", "#{THUMBNAIL_SIZE}x>",  # Resize width, keep aspect ratio, only shrink
      "-quality", WEBP_QUALITY.to_s,
      output_path,
      [:out, :err] => "/dev/null"
    )

    raise "ImageMagick convert failed" unless result && File.exist?(output_path)
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
    Rails.logger.error("Thumbnail generation failed for Score #{score.id}: #{error.message}")
  end
end
