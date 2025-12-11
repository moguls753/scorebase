require "net/http"
require "uri"
require "tempfile"

class ThumbnailGenerator
  THUMBNAIL_WIDTH = 400
  PREVIEW_WIDTH = 1200

  def initialize(score)
    @score = score
    @errors = []
  end

  def generate!
    generate_thumbnail!
  end

  def generate_thumbnail!
    return false unless @score.has_pdf?
    return true if @score.thumbnail_image.attached?

    generate_and_attach(:thumbnail_image, THUMBNAIL_WIDTH)
  rescue => e
    @errors << "Failed to generate thumbnail: #{e.message}"
    Rails.logger.error("Thumbnail generation failed for Score #{@score.id}: #{e.message}")
    false
  end

  def generate_preview!
    return false unless @score.has_pdf?
    return true if @score.preview_image.attached?

    generate_and_attach(:preview_image, PREVIEW_WIDTH)
  rescue => e
    @errors << "Failed to generate preview: #{e.message}"
    Rails.logger.error("Preview generation failed for Score #{@score.id}: #{e.message}")
    false
  end

  def generate_both!
    thumbnail_ok = generate_thumbnail!
    preview_ok = generate_preview!
    thumbnail_ok && preview_ok
  end

  def errors
    @errors
  end

  private

  def generate_and_attach(attachment_name, width)
    Tempfile.create(["score_img", ".png"]) do |output_file|
      if @score.external?
        generate_from_url(@score.pdf_path, output_file.path, width)
      else
        local_pdf_path = get_local_pdf_path
        raise "Local PDF not found" unless File.exist?(local_pdf_path)
        generate_from_file(local_pdf_path, output_file.path, width)
      end

      @score.public_send(attachment_name).attach(
        io: File.open(output_file.path),
        filename: "#{@score.id}_#{attachment_name}.png",
        content_type: "image/png"
      )
    end

    true
  end

  def generate_from_url(pdf_url, output_path, width)
    Tempfile.create(["score", ".pdf"]) do |temp_pdf|
      download_pdf(pdf_url, temp_pdf.path)
      generate_from_file(temp_pdf.path, output_path, width)
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

  def generate_from_file(pdf_path, output_path, width)
    temp_prefix = Rails.root.join("tmp", "img_#{@score.id}_#{width}_#{SecureRandom.hex(4)}")

    result = system(
      "pdftoppm",
      "-png",
      "-f", "1",
      "-singlefile",
      "-scale-to-x", width.to_s,
      "-scale-to-y", "-1",
      pdf_path.to_s,
      temp_prefix.to_s,
      [:out, :err] => "/dev/null"
    )

    raise "pdftoppm command failed" unless result

    temp_output = "#{temp_prefix}.png"
    raise "Image file not created" unless File.exist?(temp_output)

    FileUtils.mv(temp_output, output_path)
  end

  def get_local_pdf_path
    pdf_path = @score.pdf_path
    return nil if pdf_path.blank? || pdf_path == "N/A"

    File.join(ENV.fetch("PDMX_DATA_PATH", File.expand_path("~/data/pdmx")), pdf_path.sub(/^\.\//, ""))
  end
end
