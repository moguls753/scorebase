# frozen_string_literal: true

require "net/http"
require "open3"

# Extracts musical features from MusicXML using music21 Python script.
#
# Usage:
#   Music21ExtractionJob.perform_later(score.id)
#   Music21ExtractionJob.perform_now(score.id)
#
class Music21ExtractionJob < ApplicationJob
  queue_as :extraction

  retry_on StandardError, wait: 5.minutes, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  PYTHON = ENV.fetch("PYTHON_CMD", "python3")
  SCRIPT = Rails.root.join("rag/extract.py").to_s

  def perform(score_id)
    score = Score.find(score_id)
    logger.info "[Music21] Processing score ##{score.id}: #{score.title}"

    unless score.has_mxl?
      score.update!(extraction_status: "no_musicxml", extracted_at: Time.current)
      logger.info "[Music21] Skipped - no MusicXML available"
      return
    end

    Dir.mktmpdir("music21") do |dir|
      file = download_mxl(score, dir)
      result = run_python(file)
      apply_result(score, result)
      log_extraction(result)
    end
  end

  private

  def download_mxl(score, dir)
    url = score.mxl_url
    ext = File.extname(score.mxl_path).presence || ".mxl"
    path = File.join(dir, "score#{ext}")

    uri = URI(url)
    response = Net::HTTP.get_response(uri)

    # Follow redirects
    5.times do
      break unless response.is_a?(Net::HTTPRedirection)
      uri = URI(response["location"])
      response = Net::HTTP.get_response(uri)
    end

    raise "Download failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    File.binwrite(path, response.body)
    path
  end

  def run_python(file)
    stdout, stderr, status = Open3.capture3(PYTHON, SCRIPT, file)
    raise "Python failed: #{stderr.first(500)}" unless status.success?
    JSON.parse(stdout)
  end

  def apply_result(score, result)
    if result["extraction_status"] == "failed"
      score.update!(
        extraction_status: "failed",
        extraction_error: result["extraction_error"]&.first(1000),
        extracted_at: Time.current
      )
      return
    end

    score.update!(
      # Pitch & Range
      highest_pitch: result["highest_pitch"],
      lowest_pitch: result["lowest_pitch"],
      ambitus_semitones: result["ambitus_semitones"],
      pitch_range_per_part: result["pitch_range_per_part"],
      voice_ranges: result["voice_ranges"],

      # Tempo & Duration
      tempo_bpm: result["tempo_bpm"],
      tempo_marking: result["tempo_marking"],
      duration_seconds: result["duration_seconds"],
      measure_count: result["measure_count"],

      # Complexity
      note_count: result["note_count"],
      note_density: result["note_density"],
      unique_pitches: result["unique_pitches"],
      accidental_count: result["accidental_count"],
      chromatic_complexity: result["chromatic_complexity"],

      # Rhythm
      rhythm_distribution: result["rhythm_distribution"],
      syncopation_level: result["syncopation_level"],
      rhythmic_variety: result["rhythmic_variety"],
      predominant_rhythm: result["predominant_rhythm"],

      # Harmony
      key_signature: result["key_signature"] || score.key_signature,
      key_confidence: result["key_confidence"],
      key_correlations: result["key_correlations"],
      modulations: result["modulations"],
      modulation_count: result["modulation_count"],
      chord_symbols: result["chord_symbols"],
      harmonic_rhythm: result["harmonic_rhythm"],

      # Melody
      interval_distribution: result["interval_distribution"],
      largest_interval: result["largest_interval"],
      stepwise_motion_ratio: result["stepwise_motion_ratio"],
      melodic_contour: result["melodic_contour"],
      melodic_complexity: result["melodic_complexity"],

      # Structure
      time_signature: result["time_signature"] || score.time_signature,
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

      # Instrumentation
      num_parts: result["num_parts"] || score.num_parts,
      part_names: result["part_names"],
      detected_instruments: result["detected_instruments"],
      instrument_families: result["instrument_families"],
      is_vocal: result["is_vocal"],
      is_instrumental: result["is_instrumental"],
      has_accompaniment: result["has_accompaniment"],

      # Texture
      texture_type: result["texture_type"],
      polyphonic_density: result["polyphonic_density"],
      voice_independence: result["voice_independence"],

      # Metadata
      music21_version: result["music21_version"],
      musicxml_source: result["musicxml_source"],
      extraction_status: "extracted",
      extracted_at: Time.current
    )
  end

  def log_extraction(result)
    if result["extraction_status"] == "failed"
      logger.error "[Music21] Failed: #{result['extraction_error']}"
      return
    end

    logger.info "[Music21] Extracted:"
    result.each do |key, value|
      next if value.nil? || value == "" || key.start_with?("_")
      logger.info "  #{key}: #{value.inspect}"
    end
  end
end
