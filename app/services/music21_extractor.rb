# frozen_string_literal: true

require "net/http"
require "open3"

# Extracts musical features from MusicXML using music21 Python script.
#
# Usage:
#   Music21Extractor.extract(score)
#
class Music21Extractor
  PYTHON = ENV.fetch("PYTHON_CMD", "python3")
  SCRIPT = Rails.root.join("rag/extract.py").to_s

  class Error < StandardError; end

  def self.extract(score)
    new(score).extract
  end

  def initialize(score)
    @score = score
  end

  def extract
    unless @score.has_mxl?
      @score.update!(extraction_status: :no_musicxml, extracted_at: Time.current)
      return false
    end

    Dir.mktmpdir("music21") do |dir|
      file = download_mxl(dir)
      result = run_python(file)
      apply_result(result)
    end

    @score.extraction_extracted?
  rescue StandardError => e
    @score.update!(
      extraction_status: :failed,
      extraction_error: e.message.to_s[0, 500],
      extracted_at: Time.current
    )
    raise Error, e.message
  end

  private

  def download_mxl(dir)
    source = @score.mxl_url
    ext = File.extname(@score.mxl_path).presence || ".mxl"
    dest = File.join(dir, "score#{ext}")

    # Local file
    if File.exist?(source.to_s)
      FileUtils.cp(source, dest)
      return dest
    end

    # CPDL is Cloudflare-protected
    raise Error, "CPDL downloads blocked by Cloudflare" if @score.cpdl?

    # IMSLP needs cookie to bypass disclaimer
    headers = @score.imslp? ? { "Cookie" => "imslpdisclaimeraccepted=yes" } : {}

    uri = URI(source)
    response = fetch_with_redirects(uri, headers)

    raise Error, "Download failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    File.binwrite(dest, response.body)
    dest
  end

  def fetch_with_redirects(uri, headers = {}, limit = 5)
    raise Error, "Too many redirects" if limit == 0

    request = Net::HTTP::Get.new(uri)
    headers.each { |k, v| request[k] = v }

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(request)
    end

    if response.is_a?(Net::HTTPRedirection)
      location = response["location"]
      location = "#{uri.scheme}://#{uri.host}#{location}" if location.start_with?("/")
      fetch_with_redirects(URI(location), {}, limit - 1)
    else
      response
    end
  end

  def run_python(file)
    stdout, stderr, status = Open3.capture3(PYTHON, SCRIPT, file)
    raise Error, "Python failed: #{stderr[0, 500]}" unless status.success?
    JSON.parse(stdout)
  end

  def apply_result(result)
    if result["extraction_status"] == "failed"
      @score.update!(
        extraction_status: :failed,
        extraction_error: result["extraction_error"].to_s[0, 1000],
        extracted_at: Time.current
      )
      return
    end

    @score.update!(
      highest_pitch: result["highest_pitch"],
      lowest_pitch: result["lowest_pitch"],
      ambitus_semitones: result["ambitus_semitones"],
      pitch_range_per_part: result["pitch_range_per_part"],
      voice_ranges: result["voice_ranges"],
      tempo_bpm: result["tempo_bpm"],
      tempo_marking: result["tempo_marking"],
      duration_seconds: result["duration_seconds"],
      measure_count: result["measure_count"],
      note_count: result["note_count"],
      note_density: result["note_density"],
      unique_pitches: result["unique_pitches"],
      accidental_count: result["accidental_count"],
      chromatic_complexity: result["chromatic_complexity"],
      rhythm_distribution: result["rhythm_distribution"],
      syncopation_level: result["syncopation_level"],
      rhythmic_variety: result["rhythmic_variety"],
      predominant_rhythm: result["predominant_rhythm"],
      key_signature: result["key_signature"] || @score.key_signature,
      key_confidence: result["key_confidence"],
      key_correlations: result["key_correlations"],
      modulations: result["modulations"],
      modulation_count: result["modulation_count"],
      chord_symbols: result["chord_symbols"],
      harmonic_rhythm: result["harmonic_rhythm"],
      interval_distribution: result["interval_distribution"],
      largest_interval: result["largest_interval"],
      stepwise_motion_ratio: result["stepwise_motion_ratio"],
      melodic_contour: result["melodic_contour"],
      melodic_complexity: result["melodic_complexity"],
      time_signature: result["time_signature"] || @score.time_signature,
      form_analysis: result["form_analysis"],
      sections_count: result["sections_count"],
      repeats_count: result["repeats_count"],
      cadence_types: result["cadence_types"],
      final_cadence: result["final_cadence"],
      clefs_used: result["clefs_used"],
      has_dynamics: result["has_dynamics"],
      dynamic_range: result["dynamic_range"],
      has_articulations: result["has_articulations"],
      has_ornaments: result["has_ornaments"],
      has_tempo_changes: result["has_tempo_changes"],
      has_fermatas: result["has_fermatas"],
      expression_markings: result["expression_markings"],
      has_extracted_lyrics: result["has_extracted_lyrics"],
      extracted_lyrics: result["extracted_lyrics"],
      syllable_count: result["syllable_count"],
      lyrics_language: result["lyrics_language"],
      num_parts: result["num_parts"] || @score.num_parts,
      part_names: result["part_names"],
      detected_instruments: result["detected_instruments"],
      instrument_families: result["instrument_families"],
      is_vocal: result["is_vocal"],
      is_instrumental: result["is_instrumental"],
      has_accompaniment: result["has_accompaniment"],
      texture_type: result["texture_type"],
      polyphonic_density: result["polyphonic_density"],
      voice_independence: result["voice_independence"],
      music21_version: result["music21_version"],
      musicxml_source: result["musicxml_source"],
      # New fields (2024-12)
      computed_difficulty: result["computed_difficulty"],
      max_chord_span: result["max_chord_span"],
      tessitura: result["tessitura"],
      position_shift_count: result["position_shift_count"],
      position_shifts_per_measure: result["position_shifts_per_measure"],
      extraction_status: :extracted,
      extracted_at: Time.current
    )
  end
end
