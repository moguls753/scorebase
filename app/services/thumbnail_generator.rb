require "net/http"
require "uri"
require "tempfile"

class ThumbnailGenerator
  SIZES = {
    thumbnail: 400,
    preview: 1200
  }.freeze

  attr_reader :score, :errors

  def initialize(score)
    @score = score
    @errors = []
  end

  def generate(type = :both)
    return true if skip_generation?

    case type
    when :thumbnail then generate_image(:thumbnail)
    when :preview   then generate_image(:preview)
    when :both      then generate_image(:thumbnail) && generate_image(:preview)
    else
      raise ArgumentError, "Unknown type: #{type}. Use :thumbnail, :preview, or :both"
    end
  end

  private

  def skip_generation?
    score.pdmx? && score.thumbnail_url.present?
  end

  def generate_image(type)
    attachment = :"#{type}_image"
    return true if score.public_send(attachment).attached?
    return false unless score.has_pdf?

    with_pdf_file do |pdf_path|
      attach_image(attachment, pdf_path, SIZES[type])
    end
  rescue => e
    log_error(type, e)
    false
  end

  def with_pdf_file
    if score.external?
      with_downloaded_pdf { |path| yield path }
    else
      path = local_pdf_path
      raise "Local PDF not found: #{path}" unless File.exist?(path)
      yield path
    end
  end

  def with_downloaded_pdf
    Tempfile.create(["score", ".pdf"]) do |temp_pdf|
      url = score.pdf_url || score.pdf_path
      download_pdf(url, temp_pdf.path)
      yield temp_pdf.path
    end
  end

  def attach_image(attachment, pdf_path, width)
    Tempfile.create(["score_img", ".png"]) do |output|
      render_first_page(pdf_path, output.path, width)
      score.public_send(attachment).attach(
        io: File.open(output.path),
        filename: "#{score.id}_#{attachment}.png",
        content_type: "image/png"
      )
    end
    true
  end

  def render_first_page(pdf_path, output_path, width)
    temp_prefix = Rails.root.join("tmp", "img_#{score.id}_#{width}_#{SecureRandom.hex(4)}")

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

  def download_pdf(url, destination, redirect_limit: 5)
    raise "Too many redirects" if redirect_limit == 0

    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE # TODO: Proper SSL verification

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "ScorebaseBot/1.0"

    response = http.request(request)

    case response
    when Net::HTTPSuccess
      File.binwrite(destination, response.body)
    when Net::HTTPRedirection
      # Follow redirect (IMSLP uses redirects for file serving)
      redirect_url = response["location"]
      # Handle relative redirects
      redirect_url = URI.join(url, redirect_url).to_s unless redirect_url.start_with?("http")
      download_pdf(redirect_url, destination, redirect_limit: redirect_limit - 1)
    else
      raise "Failed to download PDF: #{response.code} - #{response.message}"
    end
  end

  def local_pdf_path
    pdf_path = score.pdf_path
    return nil if pdf_path.blank? || pdf_path == "N/A"

    File.join(
      ENV.fetch("PDMX_DATA_PATH", File.expand_path("~/data/pdmx")),
      pdf_path.sub(/^\.\//, "")
    )
  end

  def log_error(type, error)
    @errors << "Failed to generate #{type}: #{error.message}"
    Rails.logger.error("#{type.capitalize} generation failed for Score #{score.id}: #{error.message}")
  end
end
