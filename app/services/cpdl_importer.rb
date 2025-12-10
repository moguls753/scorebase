require "net/http"
require "json"
require "uri"

class CpdlImporter
  BASE_URL = "https://www.cpdl.org/wiki/api.php"
  BATCH_SIZE = 50  # MediaWiki API limit for many queries
  REQUEST_DELAY = 1.0  # Be nice to their servers (max 10 req/min recommended)

  # Required by MediaWiki API etiquette - see https://www.mediawiki.org/wiki/API:Etiquette
  USER_AGENT = "ScorebaseBot/1.0 (https://github.com/scorebase; contact@scorebase.app) Ruby/#{RUBY_VERSION}"

  def initialize(limit: nil)
    @limit = limit
    @imported_count = 0
    @updated_count = 0
    @skipped_count = 0
    @errors = []
  end

  def import!
    puts "Starting CPDL import..."
    puts "Limit: #{@limit || 'none'}"

    # Get all score pages from CPDL
    pages = fetch_all_score_pages
    puts "Found #{pages.size} score pages"

    pages = pages.first(@limit) if @limit

    # Process in batches
    pages.each_slice(BATCH_SIZE).with_index do |batch, batch_index|
      puts "Processing batch #{batch_index + 1} (#{@imported_count + @updated_count}/#{pages.size})..."
      process_batch(batch)
      sleep(REQUEST_DELAY) # Rate limiting
    end

    puts "\n✅ CPDL import complete!"
    puts "Imported: #{@imported_count}"
    puts "Updated: #{@updated_count}"
    puts "Skipped: #{@skipped_count}"
    puts "Errors: #{@errors.size}"

    if @errors.any?
      puts "\nFirst 10 errors:"
      @errors.first(10).each { |e| puts "  - #{e}" }
    end

    { imported: @imported_count, updated: @updated_count, skipped: @skipped_count, errors: @errors.size }
  end

  private

  def fetch_all_score_pages
    pages = []
    continue_token = nil

    loop do
      # Use category members to get all scores
      # CPDL categorizes scores under various composer categories
      params = {
        action: "query",
        list: "allpages",
        apnamespace: 0,  # Main namespace
        aplimit: 500,    # Max allowed
        format: "json"
      }
      params[:apcontinue] = continue_token if continue_token

      response = api_request(params)
      break unless response

      new_pages = response.dig("query", "allpages") || []
      pages.concat(new_pages)

      puts "  Fetched #{pages.size} pages so far..."

      # Check for continuation
      continue_token = response.dig("continue", "apcontinue")
      break unless continue_token

      sleep(REQUEST_DELAY)
    end

    # Filter to only actual score pages (not talk, help, etc.)
    # CPDL score pages typically have composer names in parentheses
    pages.select { |p| score_page?(p["title"]) }
  end

  def score_page?(title)
    # CPDL score titles typically follow pattern: "Title (Composer)"
    # Skip special pages, categories, templates, etc.
    return false if title.start_with?("Category:", "Template:", "Help:", "CPDL:", "File:")
    return false if title.include?("(page does not exist)")

    # Most score pages have composer in parentheses
    title.match?(/\(.+\)$/)
  end

  def process_batch(pages)
    pages.each do |page|
      begin
        process_page(page)
      rescue => e
        @errors << "#{page['title']}: #{e.message}"
        @skipped_count += 1
      end
    end
  end

  def process_page(page)
    title = page["title"]
    page_id = page["pageid"]

    # Fetch full page content to extract metadata
    page_data = fetch_page_content(title)
    return unless page_data

    # Parse the wiki content to extract score metadata
    metadata = parse_score_metadata(title, page_data)
    return unless metadata

    # Check if we already have this score
    existing = Score.find_by(source: "cpdl", external_id: page_id.to_s)

    if existing
      existing.update!(metadata)
      @updated_count += 1
    else
      Score.create!(metadata.merge(
        source: "cpdl",
        external_id: page_id.to_s,
        external_url: "https://www.cpdl.org/wiki/index.php/#{URI.encode_www_form_component(title)}"
      ))
      @imported_count += 1
    end
  end

  def fetch_page_content(title)
    params = {
      action: "parse",
      page: title,
      prop: "wikitext|categories",
      format: "json"
    }

    response = api_request(params)
    return nil unless response

    response["parse"]
  end

  def parse_score_metadata(title, page_data)
    wikitext = page_data.dig("wikitext", "*") || ""
    categories = (page_data["categories"] || []).map { |c| c["*"] }

    # Extract composer from title (usually in parentheses)
    composer = extract_composer_from_title(title)

    # Extract clean title
    clean_title = title.gsub(/\s*\([^)]+\)\s*$/, "").strip

    # Parse infobox/template data from wikitext
    infobox = parse_infobox(wikitext)

    # Extract voicing/parts info
    num_parts = extract_num_parts(infobox, wikitext)

    # Extract genres from categories
    genres = extract_genres(categories)

    # Get file URLs
    files = extract_file_info(wikitext)

    # Need at least a title to be valid
    return nil if clean_title.blank?

    {
      title: clean_title,
      composer: infobox["composer"] || composer,
      key_signature: infobox["key"],
      time_signature: nil,  # CPDL doesn't consistently have this
      num_parts: num_parts,
      genres: genres.join("-"),
      tags: categories.first(5).join("-"),
      complexity: nil,
      rating: nil,
      views: 0,
      favorites: 0,
      thumbnail_url: nil,
      data_path: "cpdl:#{title}",  # Use as unique identifier
      pdf_path: files[:pdf],
      mid_path: files[:midi],
      mxl_path: files[:musicxml]
    }
  end

  def extract_composer_from_title(title)
    match = title.match(/\(([^)]+)\)$/)
    match ? match[1].strip : nil
  end

  def parse_infobox(wikitext)
    info = {}

    # CPDL uses {{Infobox score}} template
    # Extract key fields
    if match = wikitext.match(/\|\s*composer\s*=\s*([^\n|]+)/i)
      info["composer"] = clean_wiki_value(match[1])
    end

    if match = wikitext.match(/\|\s*key\s*=\s*([^\n|]+)/i)
      info["key"] = clean_wiki_value(match[1])
    end

    if match = wikitext.match(/\|\s*voicing\s*=\s*([^\n|]+)/i)
      info["voicing"] = clean_wiki_value(match[1])
    end

    if match = wikitext.match(/\|\s*genre\s*=\s*([^\n|]+)/i)
      info["genre"] = clean_wiki_value(match[1])
    end

    info
  end

  def clean_wiki_value(value)
    return nil if value.blank?

    # Remove wiki links [[...]] and templates {{...}}
    value
      .gsub(/\[\[([^\]|]+)\|?[^\]]*\]\]/, '\1')  # [[Link|Text]] -> Link
      .gsub(/\{\{[^}]+\}\}/, "")                  # Remove templates
      .strip
      .presence
  end

  def extract_num_parts(infobox, wikitext)
    voicing = infobox["voicing"] || ""

    # Common voicing patterns
    case voicing.downcase
    when /satb/, /4.?part/, /four.?part/
      4
    when /sab/, /3.?part/, /three.?part/
      3
    when /sa/, /tb/, /2.?part/, /two.?part/, /duet/
      2
    when /solo/, /1.?part/, /unison/
      1
    when /\d+/
      voicing.scan(/\d+/).first.to_i
    else
      nil
    end
  end

  def extract_genres(categories)
    genre_categories = categories.select do |cat|
      cat.match?(/music|motet|anthem|mass|psalm|hymn|carol|madrigal|chanson/i)
    end

    genre_categories.map { |c| c.gsub(/_/, " ") }.first(5)
  end

  def extract_file_info(wikitext)
    files = { pdf: nil, midi: nil, musicxml: nil }

    # Look for file links in wikitext
    # Pattern: [[File:Filename.pdf]] or [[Media:Filename.pdf]]
    wikitext.scan(/\[\[(?:File|Media):([^\]|]+)/i).flatten.each do |filename|
      ext = File.extname(filename).downcase

      case ext
      when ".pdf"
        files[:pdf] ||= filename
      when ".mid", ".midi"
        files[:midi] ||= filename
      when ".xml", ".mxl", ".musicxml"
        files[:musicxml] ||= filename
      end
    end

    files
  end

  def api_request(params)
    uri = URI(BASE_URL)
    uri.query = URI.encode_www_form(params)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = USER_AGENT
    request["Accept"] = "application/json"

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      puts "  API error: #{response.code} - #{response.message}"
      return nil
    end

    JSON.parse(response.body)
  rescue => e
    puts "  Request failed: #{e.message}"
    nil
  end
end
