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

    # Save extraction data (Python extracts facts, Ruby interprets)
    @score.update!(
      # Pitch data
      highest_pitch: result["highest_pitch"],
      lowest_pitch: result["lowest_pitch"],
      ambitus_semitones: result["ambitus_semitones"],
      pitch_range_per_part: result["pitch_range_per_part"],
      voice_ranges: result["voice_ranges"],
      unique_pitches: result["unique_pitches"],
      tessitura: result["tessitura"],

      # Tempo/duration
      tempo_bpm: result["tempo_bpm"],
      tempo_marking: result["tempo_marking"],
      duration_seconds: result["duration_seconds"],
      measure_count: result["measure_count"],

      # Raw counts
      event_count: result["event_count"],
      pitch_count: result["pitch_count"],
      accidental_count: result["accidental_count"],
      leap_count: result["leap_count"],
      max_chord_span: result["max_chord_span"],
      pitch_class_distribution: result["pitch_class_distribution"],
      chromatic_ratio: result["chromatic_ratio"],

      # Rhythm (raw)
      rhythm_distribution: result["rhythm_distribution"],
      predominant_rhythm: result["predominant_rhythm"],
      unique_duration_count: result["unique_duration_count"],
      off_beat_count: result["off_beat_count"],

      # Harmony (raw)
      key_signature: result["key_signature"] || @score.key_signature,
      key_confidence: result["key_confidence"],
      key_correlations: result["key_correlations"],
      modulations: result["modulations"],
      modulation_count: result["modulation_count"],
      modulation_targets: result["modulation_targets"],
      chord_symbols: result["chord_symbols"],
      chord_count: result["chord_count"],

      # Melody (raw)
      interval_distribution: result["interval_distribution"],
      largest_interval: result["largest_interval"],
      interval_count: result["interval_count"],
      stepwise_count: result["stepwise_count"],

      # Structure
      time_signature: result["time_signature"] || @score.time_signature,
      form_analysis: result["form_analysis"],
      sections_count: result["sections_count"],
      repeats_count: result["repeats_count"],
      cadence_types: result["cadence_types"],
      final_cadence: result["final_cadence"],

      # Notation
      clefs_used: result["clefs_used"],
      has_dynamics: result["has_dynamics"],
      dynamic_range: result["dynamic_range"],
      has_articulations: result["has_articulations"],
      has_ornaments: result["has_ornaments"],
      has_tempo_changes: result["has_tempo_changes"],
      has_fermatas: result["has_fermatas"],
      expression_markings: result["expression_markings"],

      # Lyrics
      has_extracted_lyrics: result["has_extracted_lyrics"],
      extracted_lyrics: result["extracted_lyrics"],
      syllable_count: result["syllable_count"],
      lyrics_language: result["lyrics_language"],

      # Instrumentation (raw data only - has_vocal etc. set by LLM normalizers)
      num_parts: result["num_parts"] || @score.num_parts,
      part_names: result["part_names"],
      detected_instruments: result["detected_instruments"],
      instrument_families: result["instrument_families"],

      # Texture (raw)
      simultaneous_note_avg: result["simultaneous_note_avg"],
      texture_chord_count: result["texture_chord_count"],
      parallel_motion_count: result["parallel_motion_count"],

      # Phase 0: New raw extractions
      chromatic_note_count: result["chromatic_note_count"],
      meter_classification: result["meter_classification"],
      beat_count: result["beat_count"],
      voice_count: result["voice_count"],
      has_pedal_marks: result["has_pedal_marks"],
      slur_count: result["slur_count"],
      has_ottava: result["has_ottava"],
      trill_count: result["trill_count"],
      mordent_count: result["mordent_count"],
      turn_count: result["turn_count"],
      tremolo_count: result["tremolo_count"],
      grace_note_count: result["grace_note_count"],
      arpeggio_mark_count: result["arpeggio_mark_count"],
      detected_mode: result["detected_mode"],

      # Metadata
      music21_version: result["music21_version"],
      musicxml_source: result["musicxml_source"],
      extraction_status: :extracted,
      extracted_at: Time.current
    )

    # Compute derived metrics in Ruby (not from Python anymore)
    compute_derived_fields
  end

  def compute_derived_fields
    metrics = ScoreMetricsCalculator.new(@score)

    @score.update_columns(
      # Note: chromatic_ratio now comes from Python (derived fact)
      note_density: metrics.note_density,
      syncopation_level: metrics.syncopation_level,
      rhythmic_variety: metrics.rhythmic_variety,
      harmonic_rhythm: metrics.harmonic_rhythm,
      stepwise_motion_ratio: metrics.stepwise_ratio,
      voice_independence: metrics.voice_independence,
      vertical_density: metrics.vertical_density,
      leaps_per_measure: @score.measure_count&.positive? ? @score.leap_count.to_f / @score.measure_count : nil,
      computed_difficulty: DifficultyCalculator.new(@score).compute,
      texture_type: ScoreLabeler.new(@score).texture_type
    )
  end
end
