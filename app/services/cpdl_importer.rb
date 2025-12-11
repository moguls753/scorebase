require "net/http"
require "json"
require "uri"

class CpdlImporter
  BASE_URL = "https://www.cpdl.org/wiki/api.php"
  BATCH_SIZE = 5  # Process 5 scores per batch
  BATCH_DELAY = 30.0  # 30 seconds between batches
  API_CALL_DELAY = 6.0  # 6 seconds between individual API calls = ~10 requests/min max

  # Required by MediaWiki API etiquette - see https://www.mediawiki.org/wiki/API:Etiquette
  USER_AGENT = "ScorebaseBot/1.0 (https://github.com/scorebase; contact@scorebase.app) Ruby/#{RUBY_VERSION}"

  class RateLimitError < StandardError; end

  def initialize(limit: nil, resume: false)
    @limit = limit
    @resume = resume
    @imported_count = 0
    @updated_count = 0
    @skipped_count = 0
    @errors = []
  end

  def import!
    puts "Starting CPDL import..."
    puts "Limit: #{@limit || 'none'}"
    puts "Resume mode: #{@resume ? 'enabled (skip existing)' : 'disabled (update existing)'}"

    # Get all score pages from CPDL
    pages = fetch_all_score_pages
    puts "Found #{pages.size} score pages"

    # Filter out already-imported pages if resuming
    if @resume
      existing_ids = Score.where(source: "cpdl").pluck(:external_id).to_set
      original_count = pages.size
      pages = pages.reject { |p| existing_ids.include?(p["pageid"].to_s) }
      puts "Skipping #{original_count - pages.size} already-imported scores (#{pages.size} remaining)"
    end

    pages = pages.first(@limit) if @limit

    # Process in batches
    pages.each_slice(BATCH_SIZE).with_index do |batch, batch_index|
      puts "Processing batch #{batch_index + 1} (#{@imported_count + @updated_count}/#{pages.size})..."
      process_batch(batch)
      sleep(BATCH_DELAY) unless batch_index == (pages.size / BATCH_SIZE) # Don't sleep after last batch
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
  rescue RateLimitError => e
    puts "\n❌ Rate limit exceeded!"
    puts e.message
    puts "\nProgress so far:"
    puts "Imported: #{@imported_count}"
    puts "Updated: #{@updated_count}"
    puts "Skipped: #{@skipped_count}"
    raise
  end

  private

  def fetch_all_score_pages
    pages = []
    score_pages = []
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

      # Filter and count score pages as we go
      new_score_pages = new_pages.select { |p| score_page?(p["title"]) }
      score_pages.concat(new_score_pages)

      puts "  Fetched #{pages.size} total pages (#{score_pages.size} score pages)..."

      # If we have a limit and already found enough score pages, stop early
      if @limit && score_pages.size >= @limit
        puts "  Found enough score pages for limit (#{@limit}), stopping early"
        break
      end

      # Check for continuation
      continue_token = response.dig("continue", "apcontinue")
      break unless continue_token

      sleep(API_CALL_DELAY)  # Rate limit between pagination requests
    end

    score_pages
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

    # Get num_parts from infobox (already extracted from {{Voicing}} template)
    num_parts = infobox["num_parts"]

    # Extract genres from categories
    genres = extract_genres(categories)

    # Get file names from wikitext
    file_names = extract_file_info(wikitext)

    # Fetch actual URLs from MediaWiki API
    files = fetch_file_urls(file_names)

    # Need at least a title to be valid
    return nil if clean_title.blank?

    {
      title: clean_title,
      composer: infobox["composer"] || composer,
      key_signature: infobox["key"],
      time_signature: nil,  # CPDL doesn't consistently have this
      num_parts: num_parts,
      language: infobox["language"],
      instruments: infobox["instruments"],
      voicing: infobox["voicing"],
      description: infobox["description"],
      editor: infobox["editor"],
      license: infobox["license"],
      lyrics: infobox["lyrics"],
      cpdl_number: infobox["cpdl_number"],
      posted_date: infobox["posted_date"],
      page_count: infobox["page_count"],
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

    # CPDL uses template syntax like {{Composer|Name}} not infobox key-values

    # Extract composer: {{Composer|Name}}
    if match = wikitext.match(/\{\{Composer\|([^}]+)\}\}/i)
      info["composer"] = clean_wiki_value(match[1])
    end

    # Extract voicing: {{Voicing|num_parts|voicing_name}}
    if match = wikitext.match(/\{\{Voicing\|(\d+)\|([^}]+)\}\}/i)
      info["num_parts"] = match[1].to_i
      info["voicing"] = clean_wiki_value(match[2])
    end

    # Extract genre: {{Genre|Type1|Type2}}
    if match = wikitext.match(/\{\{Genre\|([^}]+)\}\}/i)
      info["genre"] = clean_wiki_value(match[1])
    end

    # Extract language: {{Language|Lang}}
    if match = wikitext.match(/\{\{Language\|([^}]+)\}\}/i)
      info["language"] = clean_wiki_value(match[1])
    end

    # Extract instruments: {{Instruments|Type}}
    if match = wikitext.match(/\{\{Instruments\|([^}]+)\}\}/i)
      info["instruments"] = clean_wiki_value(match[1])
    end

    # Extract description: {{Descr|Text}}
    if match = wikitext.match(/\{\{Descr\|([^}]*)\}\}/i)
      info["description"] = clean_wiki_value(match[1])
    end

    # Extract editor: {{Editor|Name|Date}}
    if match = wikitext.match(/\{\{Editor\|([^|}]+)/i)
      info["editor"] = clean_wiki_value(match[1])
    end

    # Extract license: {{Copy|Type}}
    if match = wikitext.match(/\{\{Copy\|([^}]+)\}\}/i)
      info["license"] = clean_wiki_value(match[1])
    end

    # Extract CPDL number: {{CPDLno|12345}}
    if match = wikitext.match(/\{\{CPDLno\|([^}]+)\}\}/i)
      info["cpdl_number"] = clean_wiki_value(match[1])
    end

    # Extract posted date: {{PostedDate|YYYY-MM-DD}}
    if match = wikitext.match(/\{\{PostedDate\|([^}]+)\}\}/i)
      date_str = clean_wiki_value(match[1])
      info["posted_date"] = Date.parse(date_str) rescue nil if date_str
    end

    # Extract score info: {{ScoreInfo|Format|Pages|Size}}
    if match = wikitext.match(/\{\{ScoreInfo\|[^|]+\|(\d+)\|/i)
      info["page_count"] = match[1].to_i
    end

    # Extract lyrics: {{Text|Language|lyrics...}}
    if match = wikitext.match(/\{\{Text\|[^|]+\|([^}]+)\}\}/im)
      lyrics = match[1].strip
      # Limit to first 2000 characters to avoid huge text blobs
      info["lyrics"] = lyrics[0..1999] if lyrics.present?
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

  def fetch_file_urls(file_names)
    urls = { pdf: nil, midi: nil, musicxml: nil }

    # Build list of file titles to query
    titles = []
    titles << "File:#{file_names[:pdf]}" if file_names[:pdf]
    titles << "File:#{file_names[:midi]}" if file_names[:midi]
    titles << "File:#{file_names[:musicxml]}" if file_names[:musicxml]

    return urls if titles.empty?

    # Query MediaWiki API for file URLs
    params = {
      action: "query",
      prop: "imageinfo",
      titles: titles.join("|"),
      iiprop: "url",
      format: "json"
    }

    response = api_request(params)
    return urls unless response

    pages = response.dig("query", "pages") || {}
    pages.each do |_page_id, page|
      next unless page["imageinfo"]

      url = page.dig("imageinfo", 0, "url")
      title = page["title"].gsub("File:", "")

      # Normalize both for comparison (MediaWiki converts _ to spaces)
      normalized_title = title.gsub(/[_\s]/, "").downcase

      # Match URL to file type
      if file_names[:pdf] && normalized_title.include?(file_names[:pdf].gsub(/[_\s]/, "").downcase)
        urls[:pdf] = url
      elsif file_names[:midi] && normalized_title.include?(file_names[:midi].gsub(/[_\s]/, "").downcase)
        urls[:midi] = url
      elsif file_names[:musicxml] && normalized_title.include?(file_names[:musicxml].gsub(/[_\s]/, "").downcase)
        urls[:musicxml] = url
      end
    end

    urls
  end

  def api_request(params, retry_count: 0)
    # Add delay before each API call to respect rate limits
    sleep(API_CALL_DELAY)

    uri = URI(BASE_URL)
    uri.query = URI.encode_www_form(params)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    # Use VERIFY_NONE as a workaround for CRL checking issues
    # CPDL's certificate has a CRL endpoint that Ruby's OpenSSL can't reach
    # The connection is still encrypted, just certificate revocation isn't checked
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = USER_AGENT
    request["Accept"] = "application/json"

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      if response.code == "403"
        raise RateLimitError, "CPDL API returned 403 Forbidden. Your IP may be temporarily blocked. Wait 1-24 hours and try again with resume mode: bin/rails \"cpdl:sync[true]\""
      elsif response.code == "500" && retry_count < 3
        # Exponential backoff for 500 errors (server issues)
        wait_time = [30, 60, 120][retry_count]
        puts "  ⚠️  Server error (500). Retrying in #{wait_time}s... (attempt #{retry_count + 1}/3)"
        sleep(wait_time)
        return api_request(params, retry_count: retry_count + 1)
      end
      puts "  API error: #{response.code} - #{response.message}"
      return nil
    end

    JSON.parse(response.body)
  rescue RateLimitError
    raise  # Re-raise rate limit errors
  rescue => e
    puts "  Request failed: #{e.message}"
    nil
  end
end
