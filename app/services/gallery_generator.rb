# Generates WebP gallery images from PDF pages and stores in Active Storage (R2)
# Each page becomes a ScorePage record with an attached image for fast CDN delivery
class GalleryGenerator
  include PdfFetchable

  GALLERY_WIDTH = 1200   # Wide enough for desktop readability
  WEBP_QUALITY = 75      # Good balance (~50KB/page)
  PDF_DENSITY = 150      # DPI for PDF rendering
  MAX_PAGES = 50         # Cap for very long scores

  attr_reader :score, :errors

  def initialize(score)
    @score = score
    @errors = []
  end

  def generate
    return true if score.has_gallery?
    return false unless score.has_pdf?

    Dir.mktmpdir("gallery") do |tmpdir|
      pdf_path = fetch_pdf_to(tmpdir)
      return add_error("Could not fetch PDF") unless pdf_path

      total_pages = pdf_page_count(pdf_path)
      return add_error("Could not determine page count") if total_pages.zero?

      pages_to_render = [total_pages, MAX_PAGES].min

      pages_to_render.times do |index|
        page_number = index + 1
        webp_path = convert_page_to_webp(pdf_path, index, tmpdir)

        if webp_path && File.exist?(webp_path)
          attach_page(webp_path, page_number)
        else
          @errors << "Failed to convert page #{page_number}"
        end
      end

      update_page_count(total_pages)
    end

    score.score_pages.any?
  end

  private

  def pdf_page_count(pdf_path)
    # Try pdfinfo first (faster), fall back to ImageMagick identify
    output = `pdfinfo "#{pdf_path}" 2>/dev/null | grep -i "^Pages:" | awk '{print $2}'`.strip
    count = output.to_i

    if count.zero?
      # Fallback: ImageMagick identify
      output = `identify -format "%n\n" "#{pdf_path}[0]" 2>/dev/null`.strip
      count = output.to_i
    end

    count
  rescue StandardError => e
    log_error(e)
    0
  end

  def convert_page_to_webp(pdf_path, page_index, tmpdir)
    output_path = File.join(tmpdir, "page_#{page_index}.webp")

    success = system(
      "convert",
      "-density", PDF_DENSITY.to_s,
      "#{pdf_path}[#{page_index}]",
      "-resize", "#{GALLERY_WIDTH}x>",
      "-quality", WEBP_QUALITY.to_s,
      "-background", "white",
      "-flatten",
      output_path,
      [:out, :err] => File::NULL
    )

    success ? output_path : nil
  rescue StandardError => e
    log_error(e)
    nil
  end

  def attach_page(webp_path, page_number)
    page = score.score_pages.find_or_initialize_by(page_number: page_number)
    page.image.attach(
      io: File.open(webp_path),
      filename: "#{score.id}_page_#{page_number}.webp",
      content_type: "image/webp"
    )
    page.save!
  rescue StandardError => e
    log_error(e)
  end

  def update_page_count(count)
    score.update_column(:page_count, count) if score.page_count.nil? || score.page_count.zero?
  end

  def add_error(message)
    @errors << message
    Rails.logger.error("[GalleryGenerator] Score ##{score.id}: #{message}")
    false
  end

  def log_error(error)
    @errors << error.message
    Rails.logger.error("[GalleryGenerator] Score ##{score.id}: #{error.message}")
  end
end
