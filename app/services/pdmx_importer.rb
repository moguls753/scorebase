require "csv"
require "json"
require "set"

class PdmxImporter
  BATCH_SIZE = 1000
  PDMX_ROOT = Pdmx.root_path

  def initialize(limit: nil, subset: "no_license_conflict")
    @limit = limit
    @subset = subset
    @imported_count = 0
    @skipped_count = 0
    @errors = []
  end

  def import!
    puts "Starting PDMX import..."
    puts "Subset: #{@subset}"
    puts "Limit: #{@limit || 'none'}"
    puts "PDMX root: #{PDMX_ROOT}"
    puts "(Existing scores are always skipped - never overwritten)"

    # Get list of files to import from subset
    subset_files = load_subset_paths

    if subset_files.empty?
      puts "ERROR: No files found in subset '#{@subset}'"
      return
    end

    puts "Found #{subset_files.size} files in subset"
    puts "Loading CSV data..."

    # Load CSV into memory (it's only 215MB)
    csv_data = load_csv_data
    puts "CSV loaded: #{csv_data.size} rows"

    # Filter to only subset files
    csv_data = csv_data.select { |row| subset_files.include?(row["path"]) }

    # Pre-filter existing to avoid duplicates
    existing_paths = Score.where(source: "pdmx").pluck(:data_path).to_set
    original_count = csv_data.size
    csv_data = csv_data.reject { |row| existing_paths.include?(row["path"]) }
    puts "Skipping #{original_count - csv_data.size} already-imported scores (#{csv_data.size} remaining)"

    csv_data = csv_data.first(@limit) if @limit

    puts "Will import #{csv_data.size} scores"

    # Process in batches
    csv_data.each_slice(BATCH_SIZE).with_index do |batch, batch_index|
      puts "Processing batch #{batch_index + 1} (#{@imported_count}/#{csv_data.size})..."
      process_batch(batch)
    end

    puts "\n✅ Import complete!"
    puts "Imported: #{@imported_count}"
    puts "Skipped: #{@skipped_count}"
    puts "Errors: #{@errors.size}"

    if @errors.any?
      puts "\nFirst 10 errors:"
      @errors.first(10).each { |e| puts "  - #{e}" }
    end
  end

  private

  def load_subset_paths
    subset_file = PDMX_ROOT.join("subset_paths", "#{@subset}.txt")

    unless subset_file.exist?
      puts "WARNING: Subset file not found: #{subset_file}"
      return Set.new
    end

    # Return as Set for O(1) lookup instead of O(n) Array lookup
    File.readlines(subset_file).map(&:strip).to_set
  end

  def load_csv_data
    csv_path = PDMX_ROOT.join("PDMX.csv")

    unless csv_path.exist?
      raise "PDMX.csv not found at #{csv_path}"
    end

    CSV.read(csv_path, headers: true)
  end

  def process_batch(batch)
    records = batch.map do |row|
      begin
        build_score_record(row)
      rescue => e
        @errors << "#{row['path']}: #{e.message}"
        @skipped_count += 1
        nil
      end
    end.compact

    # Bulk insert
    if records.any?
      Score.insert_all(records)
      @imported_count += records.size
    end
  end

  def build_score_record(csv_row)
    # Parse data JSON for key/time signatures
    data_json = parse_data_json(csv_row["path"])

    # Parse metadata JSON for thumbnails
    metadata_json = parse_metadata_json(csv_row["metadata"])

    # Extract key signature (first one if multiple)
    key_sig = extract_key_signature(data_json)

    # Extract time signature (first one if multiple)
    time_sig = extract_time_signature(data_json)

    # Extract thumbnail URL
    thumbnail_url = extract_thumbnail_url(metadata_json)

    # Build record hash
    {
      title: csv_row["song_name"].presence || csv_row["title"] || "Untitled",
      composer: csv_row["composer_name"].presence || csv_row["artist_name"],
      key_signature: key_sig,
      time_signature: time_sig,
      num_parts: csv_row["n_tracks"].to_i,
      genres: csv_row["genres"],
      tags: csv_row["tags"],
      complexity: csv_row["complexity"].to_i,
      rating: csv_row["rating"].to_f,
      views: csv_row["n_views"].to_i,
      favorites: csv_row["n_favorites"].to_i,
      thumbnail_url: thumbnail_url,
      data_path: csv_row["path"],
      metadata_path: csv_row["metadata"],
      mxl_path: csv_row["mxl"],
      pdf_path: csv_row["pdf"],
      mid_path: csv_row["mid"],
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  def parse_data_json(path)
    return nil if path.blank? || path == "N/A"

    full_path = PDMX_ROOT.join(path.delete_prefix("./"))
    return nil unless full_path.exist?

    JSON.parse(File.read(full_path))
  rescue => e
    nil
  end

  def parse_metadata_json(path)
    return nil if path.blank? || path == "N/A"

    full_path = PDMX_ROOT.join(path.delete_prefix("./"))
    return nil unless full_path.exist?

    JSON.parse(File.read(full_path))
  rescue => e
    nil
  end

  def extract_key_signature(data_json)
    return nil unless data_json

    key_sigs = data_json["key_signatures"]
    return nil unless key_sigs&.any?

    # Get first key signature
    first_key = key_sigs.first
    root = first_key["root_str"]
    mode = first_key["mode"]

    "#{root} #{mode}"
  end

  def extract_time_signature(data_json)
    return nil unless data_json

    time_sigs = data_json["time_signatures"]
    return nil unless time_sigs&.any?

    # Get first time signature
    first_time = time_sigs.first
    numerator = first_time["numerator"]
    denominator = first_time["denominator"]

    "#{numerator}/#{denominator}"
  end

  def extract_thumbnail_url(metadata_json)
    return nil unless metadata_json

    metadata_json.dig("data", "score", "thumbnails", "medium")
  rescue
    nil
  end
end
