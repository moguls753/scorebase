require "net/http"
require "uri"
require "tempfile"

class ThumbnailGenerator
  THUMBNAIL_DIR = Rails.root.join("public", "thumbnails")
  THUMBNAIL_WIDTH = 400
  THUMBNAIL_HEIGHT = 566 # A4 aspect ratio (1:1.414)

  def initialize(score)
    @score = score
    @errors = []
  end

  def generate!
    return false unless @score.has_pdf?

    # Ensure thumbnail directory exists
    FileUtils.mkdir_p(THUMBNAIL_DIR)

    # Generate thumbnail filename
    thumbnail_filename = "#{@score.id}.png"
    thumbnail_path = THUMBNAIL_DIR.join(thumbnail_filename)

    # Skip if thumbnail already exists
    if File.exist?(thumbnail_path)
      update_score_thumbnail_url(thumbnail_filename)
      return true
    end

    begin
      if @score.external?
        # Download PDF from external URL
        generate_from_url(@score.pdf_path, thumbnail_path)
      else
        # Use local PDF file
        local_pdf_path = get_local_pdf_path
        return false unless File.exist?(local_pdf_path)
        generate_from_file(local_pdf_path, thumbnail_path)
      end

      update_score_thumbnail_url(thumbnail_filename)
      true
    rescue => e
      @errors << "Failed to generate thumbnail: #{e.message}"
      Rails.logger.error("Thumbnail generation failed for Score #{@score.id}: #{e.message}")
      false
    end
  end

  def errors
    @errors
  end

  private

  def generate_from_url(pdf_url, output_path)
    # Download PDF to temp file
    Tempfile.create(["score", ".pdf"]) do |temp_pdf|
      download_pdf(pdf_url, temp_pdf.path)
      generate_from_file(temp_pdf.path, output_path)
    end
  end

  def download_pdf(url, destination)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true if uri.scheme == "https"
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE # FIXME: Proper SSL verification

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "ScorebaseBot/1.0"

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      raise "Failed to download PDF: #{response.code} - #{response.message}"
    end

    File.binwrite(destination, response.body)
  end

  def generate_from_file(pdf_path, output_path)
    # Convert first page of PDF to PNG using pdftoppm
    # pdftoppm is faster and more reliable than ImageMagick for this
    temp_prefix = Rails.root.join("tmp", "thumb_#{@score.id}")

    result = system(
      "pdftoppm",
      "-png",
      "-f", "1",           # First page only
      "-singlefile",       # Single output file
      "-scale-to-x", THUMBNAIL_WIDTH.to_s,
      "-scale-to-y", "-1", # Maintain aspect ratio
      pdf_path.to_s,
      temp_prefix.to_s,
      [:out, :err] => "/dev/null" # Suppress output
    )

    unless result
      raise "pdftoppm command failed"
    end

    # pdftoppm creates file with .png extension
    temp_output = "#{temp_prefix}.png"

    unless File.exist?(temp_output)
      raise "Thumbnail file not created"
    end

    # Move to final destination
    FileUtils.mv(temp_output, output_path)

    # Ensure file is readable
    FileUtils.chmod(0644, output_path)
  end

  def get_local_pdf_path
    pdf_path = @score.pdf_path
    return nil if pdf_path.blank? || pdf_path == "N/A"

    # Convert relative path to absolute path
    File.join(ENV.fetch("PDMX_DATA_PATH", File.expand_path("~/data/pdmx")), pdf_path.sub(/^\.\//, ""))
  end

  def update_score_thumbnail_url(filename)
    @score.update(thumbnail_url: "/thumbnails/#{filename}")
  end
end
