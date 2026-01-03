require "csv"
require "set"

class OpenscoreQuartetsImporter
  BATCH_SIZE = 500

  def self.root_path
    configured = Rails.application.config.x.openscore_quartets_path
    if configured.present? && configured.is_a?(Pathname)
      configured
    else
      Pathname.new(File.expand_path("~/data/openscore-quartets"))
    end
  end

  def initialize(limit: nil)
    @limit = limit
    @imported_count = 0
    @skipped_count = 0
    @errors = []
  end

  def import!
    puts "Starting OpenScore String Quartets import..."
    puts "Path: #{self.class.root_path}"
    puts "Limit: #{@limit || 'none'}"
    puts "(Existing scores are always skipped - never overwritten)"
    puts ""

    unless self.class.root_path.exist?
      puts "ERROR: OpenScore path not found: #{self.class.root_path}"
      puts "Clone it first: git clone --depth 1 https://github.com/OpenScore/StringQuartets.git ~/data/openscore-quartets"
      return
    end

    @composers = load_composers
    puts "Loaded #{@composers.size} composers"

    @sets = load_sets
    puts "Loaded #{@sets.size} sets"

    scores_data = load_scores
    puts "Found #{scores_data.size} scores in TSV"

    existing_paths = Score.where(source: "openscore-quartets").pluck(:data_path).to_set
    original_count = scores_data.size
    scores_data = scores_data.reject { |row| existing_paths.include?(data_path_for(row)) }
    puts "Skipping #{original_count - scores_data.size} already-imported scores (#{scores_data.size} remaining)"

    scores_data = scores_data.first(@limit) if @limit
    puts "Will import #{scores_data.size} scores"
    puts ""

    scores_data.each_slice(BATCH_SIZE).with_index do |batch, batch_index|
      puts "Processing batch #{batch_index + 1} (#{@imported_count}/#{scores_data.size})..."
      process_batch(batch)
    end

    puts ""
    puts "Import complete!"
    puts "  Imported: #{@imported_count}"
    puts "  Skipped: #{@skipped_count}"
    puts "  Errors: #{@errors.size}"

    if @errors.any?
      puts ""
      puts "First 10 errors:"
      @errors.first(10).each { |e| puts "  - #{e}" }
    end
  end

  private

  def load_composers
    path = self.class.root_path.join("data", "composers.tsv")
    return {} unless path.exist?

    composers = {}
    CSV.foreach(path, col_sep: "\t", headers: true, liberal_parsing: true) do |row|
      composers[row["id"]] = {
        name: row["name"],
        born: row["born"],
        died: row["died"]
      }
    end
    composers
  end

  def load_sets
    path = self.class.root_path.join("data", "sets.tsv")
    return {} unless path.exist?

    sets = {}
    CSV.foreach(path, col_sep: "\t", headers: true, liberal_parsing: true) do |row|
      sets[row["id"]] = {
        name: row["name"],
        composer_id: row["composer_id"]
      }
    end
    sets
  end

  def load_scores
    path = self.class.root_path.join("data", "scores.tsv")
    raise "scores.tsv not found at #{path}" unless path.exist?

    scores = []
    CSV.foreach(path, col_sep: "\t", headers: true, liberal_parsing: true) do |row|
      scores << row.to_h
    end
    scores
  end

  def data_path_for(row)
    "openscore-quartets:#{row['id']}"
  end

  def process_batch(batch)
    records = batch.map do |row|
      build_score_record(row)
    rescue => e
      @errors << "#{row['id']}: #{e.message}"
      @skipped_count += 1
      nil
    end.compact

    if records.any?
      Score.insert_all(records)
      @imported_count += records.size
    end
  end

  def build_score_record(row)
    musescore_id = row["id"]
    score_path = row["path"]

    set_info = @sets[row["set_id"]]
    composer_id = set_info&.dig(:composer_id)
    composer_info = @composers[composer_id]
    composer_name = composer_info&.dig(:name) || parse_composer_from_path(score_path)

    mxl_path = find_mxl_file(score_path, musescore_id)

    # Extract basic info from .mscx if available (for key/time sig during import)
    mscx_file = self.class.root_path.join(score_path, "sq#{musescore_id}.mscx")
    mscx_data = parse_mscx_metadata(mscx_file.to_s)

    {
      title: row["name"],
      composer: composer_name,
      source: "openscore-quartets",
      data_path: data_path_for(row),
      external_id: musescore_id,
      external_url: row["link"],
      mxl_path: mxl_path,
      key_signature: mscx_data[:key_signature],
      time_signature: mscx_data[:time_signature],
      num_parts: mscx_data[:num_parts] || 4,
      part_names: mscx_data[:part_names],
      genre: "String quartet",
      period: infer_period(composer_info),
      is_vocal: false,
      instruments: mscx_data[:part_names] || "Violin I, Violin II, Viola, Cello",
      license: "CC0",
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  def parse_composer_from_path(path)
    return nil if path.blank?
    parts = path.split("/")
    return nil if parts.empty?
    parts.first.tr("_", " ")
  end

  def find_mxl_file(score_path, musescore_id)
    dir = self.class.root_path.join(score_path)
    mxl_file = dir.join("sq#{musescore_id}.mxl")

    if mxl_file.exist?
      "./#{score_path}/sq#{musescore_id}.mxl"
    else
      found = Dir.glob(dir.join("*.mxl")).first
      found ? "./#{score_path}/#{File.basename(found)}" : nil
    end
  end

  def parse_mscx_metadata(mscx_path)
    return {} unless mscx_path && File.exist?(mscx_path)

    content = File.read(mscx_path, encoding: "UTF-8")

    key_sig = extract_key_from_mscx(content)
    time_sig = extract_time_from_mscx(content)
    num_parts = content.scan(/<Part>/).size
    part_names = content.scan(/<Part>.*?<trackName>([^<]+)<\/trackName>/m).flatten.first(num_parts)

    {
      key_signature: key_sig,
      time_signature: time_sig,
      num_parts: num_parts.positive? ? num_parts : nil,
      part_names: part_names.any? ? part_names.uniq.join(", ") : nil
    }
  rescue
    {}
  end

  def extract_key_from_mscx(content)
    match = content.match(/<KeySig>\s*<accidental>(-?\d+)<\/accidental>/)
    return nil unless match

    accidentals = match[1].to_i
    key_map = {
      0 => "C major", 1 => "G major", 2 => "D major", 3 => "A major",
      4 => "E major", 5 => "B major", 6 => "F# major", 7 => "C# major",
      -1 => "F major", -2 => "Bb major", -3 => "Eb major", -4 => "Ab major",
      -5 => "Db major", -6 => "Gb major", -7 => "Cb major"
    }
    key_map[accidentals]
  end

  def extract_time_from_mscx(content)
    n_match = content.match(/<sigN>(\d+)<\/sigN>/)
    d_match = content.match(/<sigD>(\d+)<\/sigD>/)
    return nil unless n_match && d_match
    "#{n_match[1]}/#{d_match[1]}"
  end

  def infer_period(composer_info)
    return nil unless composer_info
    born = composer_info[:born].to_i
    return nil if born == 0

    case born
    when 0..1600 then "Renaissance"
    when 1601..1750 then "Baroque"
    when 1751..1820 then "Classical"
    when 1821..1910 then "Romantic"
    else "Modern"
    end
  end
end
