require "net/http"
require "json"
require "uri"

class ImslpImporter
  # IMSLP API endpoints
  WORKLIST_API = "https://imslp.org/imslpscripts/API.ISCR.php"
  MEDIAWIKI_API = "https://imslp.org/api.php"

  # Conservative rate limiting (2s per user preference)
  BATCH_SIZE = 10           # Process 10 works per batch
  BATCH_DELAY = 30.0        # 30 seconds between batches
  API_CALL_DELAY = 2.0      # 2 seconds between individual API calls
  WORKLIST_PAGE_SIZE = 1000 # IMSLP returns 1000 per page

  # Required by MediaWiki API etiquette - see https://www.mediawiki.org/wiki/API:Etiquette
  USER_AGENT = "ScorebaseBot/1.0 (https://github.com/scorebase; contact@scorebase.app) Ruby/#{RUBY_VERSION}"

  class RateLimitError < StandardError; end
  class ApiError < StandardError; end

  # Key signature mapping from IMSLP format to readable format
  KEY_MAPPINGS = {
    # Major keys
    "C" => "C major", "c" => "C major",
    "G" => "G major", "g" => "G major",
    "D" => "D major", "d" => "D major",
    "A" => "A major", "a" => "A major",
    "E" => "E major", "e" => "E major",
    "B" => "B major", "b" => "B major",
    "F" => "F major", "f" => "F major",
    "Bb" => "B-flat major", "B♭" => "B-flat major",
    "Eb" => "E-flat major", "E♭" => "E-flat major",
    "Ab" => "A-flat major", "A♭" => "A-flat major",
    "Db" => "D-flat major", "D♭" => "D-flat major",
    "Gb" => "G-flat major", "G♭" => "G-flat major",
    "Cb" => "C-flat major", "C♭" => "C-flat major",
    "F#" => "F-sharp major", "F♯" => "F-sharp major",
    "C#" => "C-sharp major", "C♯" => "C-sharp major",
    # Minor keys (IMSLP uses lowercase or suffix)
    "c-" => "C minor", "Cm" => "C minor", "cm" => "C minor",
    "g-" => "G minor", "Gm" => "G minor", "gm" => "G minor",
    "d-" => "D minor", "Dm" => "D minor", "dm" => "D minor",
    "a-" => "A minor", "Am" => "A minor", "am" => "A minor",
    "e-" => "E minor", "Em" => "E minor", "em" => "E minor",
    "b-" => "B minor", "Bm" => "B minor", "bm" => "B minor",
    "f-" => "F minor", "Fm" => "F minor", "fm" => "F minor",
    "f#-" => "F-sharp minor", "F#m" => "F-sharp minor",
    "c#-" => "C-sharp minor", "C#m" => "C-sharp minor",
    "g#-" => "G-sharp minor", "G#m" => "G-sharp minor",
    "d#-" => "D-sharp minor", "D#m" => "D-sharp minor",
    "a#-" => "A-sharp minor", "A#m" => "A-sharp minor",
    "bb-" => "B-flat minor", "Bbm" => "B-flat minor",
    "eb-" => "E-flat minor", "Ebm" => "E-flat minor",
    "ab-" => "A-flat minor", "Abm" => "A-flat minor"
  }.freeze

  def initialize(limit: nil, resume: false, start_offset: 0)
    @limit = limit
    @resume = resume
    @start_offset = start_offset
    @imported_count = 0
    @updated_count = 0
    @skipped_count = 0
    @errors = []
    @current_offset = start_offset
  end

  def import!
    puts "Starting IMSLP import..."
    puts "Limit: #{@limit || 'none'}"
    puts "Resume mode: #{@resume ? 'enabled (skip existing)' : 'disabled (update existing)'}"
    puts "Start offset: #{@start_offset}"
    puts ""

    # Phase 1: Fetch work list from IMSLP API
    puts "Phase 1: Fetching work list from IMSLP..."
    works = fetch_all_works
    puts "Found #{works.size} works"

    # Phase 2: Filter if resume mode
    if @resume
      existing_ids = Score.where(source: "imslp").pluck(:external_id).to_set
      original_count = works.size
      works = works.reject { |w| existing_ids.include?(w.dig("intvals", "pageid").to_s) }
      puts "Skipping #{original_count - works.size} already-imported works (#{works.size} remaining)"
    end

    return report_results if works.empty?

    # Phase 3: Process in batches
    puts ""
    puts "Phase 2: Fetching details and importing..."
    total_batches = (works.size.to_f / BATCH_SIZE).ceil

    works.each_slice(BATCH_SIZE).with_index do |batch, batch_index|
      puts "Batch #{batch_index + 1}/#{total_batches} (#{@imported_count + @updated_count + @skipped_count}/#{works.size})..."
      process_batch(batch)

      # Don't sleep after last batch
      sleep(BATCH_DELAY) unless batch_index == total_batches - 1

      # Periodic progress report for long imports
      if (batch_index + 1) % 50 == 0
        puts "  Checkpoint: #{@imported_count} imported, #{@updated_count} updated, #{@errors.size} errors"
      end
    end

    # Batch normalize all composers at the end
    puts "\nPhase 3: Normalizing composers..."
    normalize_composers_batch!

    report_results
  rescue RateLimitError => e
    puts "\n[ERROR] Rate limit exceeded!"
    puts e.message
    puts "\nTo resume, run with start_offset: #{@current_offset}"
    report_results
    raise
  end

  private

  def fetch_all_works
    works = []
    offset = @start_offset

    loop do
      puts "  Fetching works page at offset #{offset}..."
      @current_offset = offset

      response = fetch_works_page(offset)
      break unless response

      # Extract works (skip metadata entry)
      page_works = response.reject { |k, _| k == "metadata" }.values
      works.concat(page_works)

      puts "  Total works collected: #{works.size}"

      # Check pagination
      more_available = response.dig("metadata", "moreresultsavailable")
      break unless more_available
      break if @limit && works.size >= @limit

      offset += WORKLIST_PAGE_SIZE
      sleep(API_CALL_DELAY)
    end

    works = works.first(@limit) if @limit
    works
  end

  def fetch_works_page(start_offset)
    # IMSLP worklist API uses path-style parameters
    url = "#{WORKLIST_API}?account=worklist/disclaimer=accepted/sort=id/type=2/start=#{start_offset}/retformat=json"
    api_request(url)
  end

  def fetch_work_details(page_title)
    params = {
      action: "parse",
      page: page_title,
      prop: "wikitext|categories",
      format: "json"
    }

    response = api_request(MEDIAWIKI_API, params)
    return nil unless response

    # Handle redirects
    wikitext = response.dig("parse", "wikitext", "*")
    if wikitext&.start_with?("#REDIRECT")
      redirect_match = wikitext.match(/\[\[([^\]]+)\]\]/)
      if redirect_match
        puts "    Following redirect to: #{redirect_match[1]}"
        params[:page] = redirect_match[1]
        response = api_request(MEDIAWIKI_API, params)
      end
    end

    response&.dig("parse")
  end

  def process_batch(works)
    works.each do |work|
      begin
        process_work(work)
      rescue => e
        work_id = work.dig("intvals", "pageid") || work["id"]
        @errors << "#{work_id}: #{e.message}"
        @skipped_count += 1
      end
    end
  end

  def process_work(work_entry)
    intvals = work_entry["intvals"] || {}
    page_id = intvals["pageid"].to_s
    permlink = work_entry["permlink"].to_s

    # Extract page title from permlink
    page_title = extract_page_title(permlink)
    return if page_title.blank?

    # Skip if in resume mode and already exists
    if @resume
      existing = Score.find_by(source: "imslp", external_id: page_id)
      if existing
        @skipped_count += 1
        return
      end
    end

    # Fetch detailed metadata
    puts "  Processing: #{intvals['worktitle'] || page_title}"
    details = fetch_work_details(page_title)
    unless details
      @skipped_count += 1
      return
    end

    # Parse wikitext
    wikitext = details.dig("wikitext", "*") || ""
    categories = (details["categories"] || []).map { |c| c["*"] }
    parsed = parse_wikitext(wikitext)
    parsed[:categories] = categories

    # Build score attributes
    attributes = build_score_attributes(work_entry, parsed)

    # Skip if missing required fields
    if attributes[:title].blank? || attributes[:data_path].blank?
      @skipped_count += 1
      return
    end

    # Create or update
    existing = Score.find_by(source: "imslp", external_id: page_id)

    if existing
      existing.update!(attributes.except(:source, :external_id, :data_path))
      @updated_count += 1
    else
      Score.create!(attributes)
      @imported_count += 1
    end
  end

  def extract_page_title(permlink)
    return nil if permlink.blank?

    # Extract page title from URL like https://imslp.org/wiki/Title_(Composer)
    if permlink.include?("/wiki/")
      title = permlink.split("/wiki/").last
      URI.decode_www_form_component(title.to_s)
    else
      nil
    end
  end

  def parse_wikitext(wikitext)
    return {} if wikitext.blank?

    info = {}

    # Work-level metadata (pipe-delimited key=value)
    info[:title] = extract_field(wikitext, "Work Title")
    info[:alternative_title] = extract_field(wikitext, "Alternative Title")
    info[:opus] = extract_field(wikitext, "Opus/Catalogue Number")
    info[:key] = extract_key_field(wikitext)
    info[:year] = extract_field(wikitext, "Year/Date of Composition")
    info[:first_performance] = extract_field(wikitext, "First Performance")
    info[:dedication] = extract_field(wikitext, "Dedication")
    info[:average_duration] = extract_field(wikitext, "Average Duration")
    info[:instrumentation] = extract_field(wikitext, "Instrumentation")
    info[:instr_detail] = extract_field(wikitext, "InstrDetail")
    info[:piece_style] = extract_field(wikitext, "Piece Style")
    info[:language] = extract_field(wikitext, "Language")
    info[:librettist] = extract_field(wikitext, "Librettist")
    info[:movements] = extract_field(wikitext, "Number of Movements/Sections")
    info[:tags] = extract_field(wikitext, "Tags")

    # Extract file information (PDFs, MusicXML, MIDI)
    info[:files] = extract_file_entries(wikitext)

    info
  end

  def extract_field(wikitext, field_name)
    # Match |Field Name=value (multiline aware, stop at next pipe or newline+pipe)
    pattern = /\|#{Regexp.escape(field_name)}=([^\n|]*(?:\n(?!\|)[^\n|]*)*)/m
    match = wikitext.match(pattern)
    return nil unless match

    clean_wiki_value(match[1].strip)
  end

  def extract_key_field(wikitext)
    # Special handling for {{Key|x}} template
    if match = wikitext.match(/\|Key=\s*\{\{[Kk]ey\|([^}|]+)/)
      key_code = match[1].strip
      KEY_MAPPINGS[key_code] || key_code
    else
      extract_field(wikitext, "Key")
    end
  end

  def extract_file_entries(wikitext)
    files = { pdf: [], musicxml: [], midi: [] }

    # Match {{#fte:imslpfile ... }} blocks
    wikitext.scan(/\{\{#fte:imslpfile(.*?)\}\}/m).each do |match|
      block = match[0]

      # Try multiple filename fields (File Name 1, File Name 2, etc.)
      (1..25).each do |i|
        filename_match = block.match(/\|File Name #{i}=([^\|\n]+)/)
        next unless filename_match

        filename = filename_match[1].strip
        next if filename.blank?

        ext = File.extname(filename).downcase

        file_info = {
          filename: filename,
          description: extract_block_field(block, "File Description #{i}"),
          editor: extract_editor(block),
          copyright: extract_block_field(block, "Copyright"),
          image_type: extract_block_field(block, "Image Type"),
          date_submitted: extract_block_field(block, "Date Submitted")
        }

        case ext
        when ".pdf"
          files[:pdf] << file_info
        when ".xml", ".mxl", ".musicxml"
          files[:musicxml] << file_info
        when ".mid", ".midi"
          files[:midi] << file_info
        end
      end
    end

    files
  end

  def extract_block_field(block, field_name)
    match = block.match(/\|#{Regexp.escape(field_name)}=([^\|\n]+)/)
    match ? clean_wiki_value(match[1].strip) : nil
  end

  def extract_editor(block)
    # Handle {{LinkEd|First|Last}} or {{FE}} templates
    if match = block.match(/\|Editor=\{\{LinkEd\|([^|]+)\|([^|}]+)/)
      "#{match[1]} #{match[2]}"
    elsif block.include?("{{FE}}")
      "First Edition"
    else
      extract_block_field(block, "Editor")
    end
  end

  def clean_wiki_value(value)
    return nil if value.blank?

    value
      .gsub(/\{\{[^}]*\}\}/, "")               # Remove templates
      .gsub(/\[\[([^\]|]+)\|?[^\]]*\]\]/, '\1') # [[Link|Text]] -> Link
      .gsub(/<[^>]+>/, "")                      # Remove HTML tags
      .gsub(/\n+/, " ")                         # Normalize newlines
      .gsub(/\s+/, " ")                         # Normalize whitespace
      .strip
      .presence
  end

  def build_score_attributes(work_entry, parsed)
    intvals = work_entry["intvals"] || {}
    files = parsed[:files] || {}

    # Select best file for each type (prefer typeset over scans)
    pdf_file = select_best_file(files[:pdf])
    musicxml_file = select_best_file(files[:musicxml])
    midi_file = select_best_file(files[:midi])

    # Get thumbnail URL from PDF preview (actual score page, not cover image)
    thumb_url = build_thumbnail_url(pdf_file&.dig(:filename))

    # Extract voicing and num_parts from instrumentation
    voicing_info = parse_voicing(parsed[:instrumentation], parsed[:instr_detail])

    {
      # Core identifiers
      source: "imslp",
      external_id: intvals["pageid"].to_s,
      external_url: work_entry["permlink"],
      data_path: "imslp:#{intvals['pageid']}",

      # Metadata
      title: parsed[:title] || intvals["worktitle"] || "Untitled",
      composer: normalize_composer(intvals["composer"]),
      key_signature: parsed[:key],
      time_signature: nil,  # Not available in IMSLP metadata
      num_parts: voicing_info[:num_parts],
      voicing: voicing_info[:voicing],
      instruments: parsed[:instrumentation],
      language: parsed[:language],
      description: build_description(parsed),
      editor: pdf_file&.dig(:editor) || musicxml_file&.dig(:editor),
      license: normalize_license(pdf_file&.dig(:copyright)),

      # Classification
      genres: build_genres(parsed[:piece_style], parsed[:tags], parsed[:categories]),
      tags: parsed[:tags]&.gsub(/\s*;\s*/, "-"),
      complexity: nil,

      # Stats (not available from IMSLP)
      rating: nil,
      views: 0,
      favorites: 0,

      # Dates
      posted_date: parse_date(pdf_file&.dig(:date_submitted)),
      page_count: nil,

      # File paths (store filenames)
      pdf_path: pdf_file&.dig(:filename),
      mxl_path: musicxml_file&.dig(:filename),
      mid_path: midi_file&.dig(:filename),

      thumbnail_url: thumb_url,
      cpdl_number: nil
    }
  end

  def build_thumbnail_url(pdf_filename)
    # Fetch PDF preview from MediaWiki API - this generates an actual score page preview
    return nil if pdf_filename.blank?

    fetch_pdf_thumbnail_url(pdf_filename, 400)
  end

  def fetch_pdf_thumbnail_url(filename, width)
    params = {
      action: "query",
      titles: "File:#{filename}",
      prop: "imageinfo",
      iiprop: "url",
      iiurlwidth: width,
      format: "json"
    }

    response = api_request(MEDIAWIKI_API, params)
    return nil unless response

    pages = response.dig("query", "pages") || {}
    page = pages.values.first
    return nil unless page && page["imageinfo"]

    # Get the thumb URL - this is a PNG preview of the PDF's first page
    thumb_url = page.dig("imageinfo", 0, "thumburl")
    return nil if thumb_url.blank?

    # Ensure https and convert protocol-relative URLs
    thumb_url = "https:#{thumb_url}" if thumb_url.start_with?("//")
    thumb_url.sub("http://", "https://")
  end

  def normalize_composer(composer_str)
    return nil if composer_str.blank?

    # Check cache first
    @composer_cache ||= load_composer_cache
    return @composer_cache[composer_str] if @composer_cache.key?(composer_str)

    # Queue for batch processing
    @composer_queue ||= []
    @composer_queue << composer_str

    # Fallback for now - batch will update later
    composer_str
  end

  def normalize_composers_batch!
    return if @composer_queue.blank?

    api_key = ENV["GEMINI_API_KEY"]
    return unless api_key.present?

    @composer_cache ||= load_composer_cache
    uncached = @composer_queue.uniq - @composer_cache.keys
    return if uncached.empty?

    puts "  Normalizing #{uncached.size} composers via Gemini..."

    uncached.each_slice(40) do |batch|
      results = gemini_normalize_batch(api_key, batch)
      next unless results

      results.each do |item|
        @composer_cache[item["original"]] = item["normalized"]
      end

      sleep 4 # Rate limit
    end

    save_composer_cache
    @composer_queue = []

    # Update scores with normalized composers
    @composer_cache.each do |original, normalized|
      next unless normalized
      Score.where(source: "imslp", composer: original).update_all(composer: normalized)
    end
  end

  def gemini_normalize_batch(api_key, composers)
    uri = URI("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-lite:generateContent?key=#{api_key}")

    prompt = <<~PROMPT
      Normalize these composer names to "LastName, FirstName" format.
      Use native language names (German composers get German names).
      Return JSON: [{"original": "input", "normalized": "Name" or null}]

      Input: #{composers.to_json}
    PROMPT

    body = {
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: { responseMimeType: "application/json", temperature: 0.1 }
    }

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.verify_callback = ->(_ok, _ctx) { true }
    http.read_timeout = 60

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req.body = body.to_json

    res = http.request(req)
    return nil unless res.code == "200"

    JSON.parse(JSON.parse(res.body).dig("candidates", 0, "content", "parts", 0, "text"))
  rescue => e
    puts "  Batch normalization failed: #{e.message}"
    nil
  end

  def load_composer_cache
    AppSetting.get("composer_cache") || {}
  end

  def save_composer_cache
    AppSetting.set("composer_cache", @composer_cache)
  end

  def parse_voicing(instrumentation, instr_detail)
    return { voicing: nil, num_parts: nil } if instrumentation.blank?

    instr = instrumentation.downcase

    # Common vocal patterns
    if instr.include?("satb")
      { voicing: "SATB", num_parts: 4 }
    elsif instr.include?("ssaattbb")
      { voicing: "SSAATTBB", num_parts: 8 }
    elsif instr.include?("ssaa")
      { voicing: "SSAA", num_parts: 4 }
    elsif instr.include?("ttbb")
      { voicing: "TTBB", num_parts: 4 }
    elsif instr.include?("sab")
      { voicing: "SAB", num_parts: 3 }
    elsif instr.match?(/\bsa\b/)
      { voicing: "SA", num_parts: 2 }
    elsif instr.match?(/\btb\b/)
      { voicing: "TB", num_parts: 2 }
    elsif match = instr.match(/(\d+)\s*voices?/i)
      { voicing: "#{match[1]}vv", num_parts: match[1].to_i }
    elsif instr.include?("solo") || instr.include?("voice")
      { voicing: "Solo", num_parts: 1 }
    else
      { voicing: nil, num_parts: nil }
    end
  end

  def normalize_license(copyright_str)
    return nil if copyright_str.blank?

    case copyright_str.downcase
    when /public domain/
      "Public Domain"
    when /creative commons.*attribution.*sharealike.*4/
      "CC BY-SA 4.0"
    when /creative commons.*attribution.*sharealike/
      "CC BY-SA 3.0"
    when /creative commons.*attribution.*noncommercial.*4/
      "CC BY-NC 4.0"
    when /creative commons.*attribution.*noncommercial/
      "CC BY-NC 3.0"
    when /creative commons.*attribution.*4/
      "CC BY 4.0"
    when /creative commons.*attribution/
      "CC BY 3.0"
    when /creative commons zero/, /cc0/
      "CC0 1.0"
    else
      copyright_str[0..50]
    end
  end

  def select_best_file(files)
    return nil if files.blank?

    # Prefer typeset over scans, then by date (newest first)
    files.sort_by do |f|
      type_score = case f[:image_type]&.downcase
      when /typeset/ then 0
      when /normal scan/ then 1
      when /manuscript/ then 2
      else 3
      end
      [type_score, -(f[:date_submitted]&.to_s || "0000")]
    end.first
  end

  def build_genres(piece_style, tags, categories)
    genres = []
    genres << piece_style if piece_style.present?

    # Extract genre-like categories
    if categories.present?
      genre_patterns = %w[masses motets anthems psalms hymns carols madrigals chansons operas symphonies sonatas concertos requiems cantatas oratorios preludes fugues]
      categories.each do |cat|
        genres << cat if genre_patterns.any? { |p| cat.downcase.include?(p) }
      end
    end

    genres.uniq.first(5).join("-")
  end

  def build_description(parsed)
    parts = []
    parts << "Op. #{parsed[:opus]}" if parsed[:opus].present?
    parts << "Composed: #{parsed[:year]}" if parsed[:year].present?
    parts << "Duration: #{parsed[:average_duration]}" if parsed[:average_duration].present?
    parts << "Movements: #{parsed[:movements]}" if parsed[:movements].present?
    parts << "Dedicated to: #{parsed[:dedication]}" if parsed[:dedication].present?

    parts.join(". ").presence
  end

  def parse_date(date_str)
    return nil if date_str.blank?
    # IMSLP format: YYYY/M/D
    Date.parse(date_str.gsub("/", "-")) rescue nil
  end

  def api_request(url, params = nil, retry_count: 0)
    # Enforce rate limit before every request
    sleep(API_CALL_DELAY)

    uri = URI(url)
    uri.query = URI.encode_www_form(params) if params&.any?

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    # Use VERIFY_NONE as a workaround for CRL checking issues
    # IMSLP's certificate has a CRL endpoint that Ruby's OpenSSL can't reach
    # The connection is still encrypted, just certificate revocation isn't checked
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    http.open_timeout = 30
    http.read_timeout = 60

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = USER_AGENT
    request["Accept"] = "application/json"

    response = http.request(request)

    case response.code
    when "200"
      JSON.parse(response.body)
    when "403"
      raise RateLimitError, "IMSLP API returned 403 Forbidden. IP may be temporarily blocked. Wait 1-24 hours. Current offset: #{@current_offset}"
    when "429"
      if retry_count < 3
        wait_time = [60, 120, 300][retry_count]
        puts "  Rate limited (429). Waiting #{wait_time}s... (attempt #{retry_count + 1}/3)"
        sleep(wait_time)
        return api_request(url, params, retry_count: retry_count + 1)
      end
      raise RateLimitError, "IMSLP rate limit exceeded after retries. Current offset: #{@current_offset}"
    when "500", "502", "503", "504"
      if retry_count < 3
        wait_time = [30, 60, 120][retry_count]
        puts "  Server error (#{response.code}). Retrying in #{wait_time}s... (attempt #{retry_count + 1}/3)"
        sleep(wait_time)
        return api_request(url, params, retry_count: retry_count + 1)
      end
      raise ApiError, "IMSLP server error: #{response.code}"
    else
      puts "  API error: #{response.code} - #{response.message}"
      nil
    end
  rescue RateLimitError, ApiError
    raise
  rescue => e
    puts "  Request failed: #{e.message}"
    nil
  end

  def report_results
    puts ""
    puts "=" * 50
    puts "IMSLP import complete!"
    puts "Imported: #{@imported_count}"
    puts "Updated: #{@updated_count}"
    puts "Skipped: #{@skipped_count}"
    puts "Errors: #{@errors.size}"

    if @errors.any?
      puts ""
      puts "First 10 errors:"
      @errors.first(10).each { |e| puts "  - #{e}" }
    end

    {
      imported: @imported_count,
      updated: @updated_count,
      skipped: @skipped_count,
      errors: @errors.size,
      last_offset: @current_offset
    }
  end
end
