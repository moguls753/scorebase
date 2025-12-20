module ScoresHelper
  # Single source of truth for filter parameters
  FILTER_PARAMS = %i[key time voicing voice_type genre period source difficulty language].freeze

  # Count active filters from params
  def active_filters_count
    FILTER_PARAMS.count { |param| params[param].present? }
  end

  # Generate hidden fields for all filter params to preserve state across forms
  def filter_hidden_fields(form)
    safe_join(FILTER_PARAMS.map { |param| form.hidden_field(param, value: params[param]) })
  end

  # ─────────────────────────────────────────────────────────────────
  # Score Show Page Helpers
  # ─────────────────────────────────────────────────────────────────

  # Section header with icon and title
  # Usage: score_section_header("♪", "score.music_details")
  def score_section_header(icon, title_key)
    content_tag(:h3, class: "score-section-header") do
      content_tag(:span, icon, class: "score-section-icon") + t(title_key)
    end
  end

  # Render a detail item for the metadata grid
  # Returns nil if value is blank (safe to chain without conditionals)
  def score_detail_item(label_key, value, full_width: false, mono: false)
    return if value.blank?

    css_class = "score-detail-item"
    css_class += " score-detail-item-full" if full_width

    content_tag(:div, class: css_class) do
      content_tag(:dt, t(label_key)) +
        content_tag(:dd, value, class: mono ? "font-mono" : nil)
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Music21 Extracted Data Helpers
  # ─────────────────────────────────────────────────────────────────

  # Format duration in seconds to human-readable "~3 min" or "~1 min 30 sec"
  def format_duration(seconds)
    return nil if seconds.blank? || seconds <= 0

    minutes = (seconds / 60).floor
    remaining_seconds = (seconds % 60).round

    if minutes == 0
      "~#{remaining_seconds} sec"
    elsif remaining_seconds == 0 || remaining_seconds < 15
      "~#{minutes} min"
    else
      "~#{minutes} min #{remaining_seconds} sec"
    end
  end

  # Format tempo: "Andante (♩= 72)" or just "72 BPM"
  def format_tempo(marking, bpm)
    return nil if marking.blank? && bpm.blank?

    if marking.present? && bpm.present?
      "#{marking} (♩= #{bpm})"
    elsif marking.present?
      marking
    else
      "♩= #{bpm}"
    end
  end

  # Format pitch range: "C3 – G5"
  def format_pitch_range(low, high)
    return nil if low.blank? || high.blank?
    "#{low} – #{high}"
  end

  # Check if score has extracted analysis data
  def has_extracted_data?(score)
    score.extraction_status == "extracted"
  end

  # Build array of analysis metrics for display
  # Returns array of {icon:, value:, label:} hashes
  def analysis_metrics(score)
    metrics = []

    if score.duration_seconds.to_i.positive?
      metrics << { icon: "◷", value: format_duration(score.duration_seconds), label: t("score.duration") }
    end

    if score.tempo_bpm.present? || score.tempo_marking.present?
      metrics << { icon: "♩", value: format_tempo(score.tempo_marking, score.tempo_bpm), label: t("score.tempo") }
    end

    if score.lowest_pitch.present? && score.highest_pitch.present?
      metrics << { icon: "↕", value: format_pitch_range(score.lowest_pitch, score.highest_pitch), label: t("score.range") }
    end

    if score.measure_count.to_i.positive?
      metrics << { icon: "𝄀", value: score.measure_count, label: t("score.measures") }
    end

    metrics
  end

  # Check if score has vocal range data worth showing
  def has_vocal_ranges?(score)
    score.pitch_range_per_part.present? && score.pitch_range_per_part.keys.length > 1
  end

  # Notation feature definitions: icon + i18n key
  NOTATION_FEATURES = [
    { key: :has_dynamics,      icon: "𝆏", label_key: "score.badge_dynamics" },
    { key: :has_ornaments,     icon: "𝄢", label_key: "score.badge_ornaments" },
    { key: :has_articulations, icon: "·", label_key: "score.badge_articulations" },
    { key: :has_fermatas,      icon: "𝄐", label_key: "score.badge_fermatas" }
  ].freeze

  # Get feature badges with icons for display
  def notation_feature_badges(score)
    return [] unless has_extracted_data?(score)

    NOTATION_FEATURES.filter_map do |feature|
      next unless score.public_send(feature[:key])
      { icon: feature[:icon], label: t(feature[:label_key]) }
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Vocal Range Helpers
  # ─────────────────────────────────────────────────────────────────

  # MIDI reference range for visualization (C2 to C6 = common vocal range)
  MIDI_RANGE_MIN = 36  # C2
  MIDI_RANGE_MAX = 84  # C6

  # Format vocal range from hash: "C3 – G5"
  def format_part_range(range_data)
    low, high = extract_range(range_data)
    return nil if low.blank? || high.blank?
    "#{low} – #{high}"
  end

  # Calculate CSS style for vocal range bar visualization
  def vocal_range_bar_style(range_data)
    low, high = extract_range(range_data)
    return "" if low.blank? || high.blank?

    low_midi = pitch_to_midi(low)
    high_midi = pitch_to_midi(high)
    return "" if low_midi.nil? || high_midi.nil?

    range_span = MIDI_RANGE_MAX - MIDI_RANGE_MIN
    left_pct = clamp((low_midi - MIDI_RANGE_MIN).to_f / range_span * 100)
    right_pct = clamp((high_midi - MIDI_RANGE_MIN).to_f / range_span * 100)
    width_pct = [right_pct - left_pct, 5].max # Minimum 5% width for visibility

    "left: #{left_pct.round(1)}%; width: #{width_pct.round(1)}%"
  end

  # ─────────────────────────────────────────────────────────────────
  # Debug Helpers
  # ─────────────────────────────────────────────────────────────────

  EXTRACTION_FIELDS = %w[
    extraction_status extracted_at music21_version
    highest_pitch lowest_pitch ambitus_semitones pitch_range_per_part voice_ranges
    tempo_bpm tempo_marking duration_seconds measure_count
    note_count note_density unique_pitches accidental_count chromatic_complexity
    rhythm_distribution syncopation_level rhythmic_variety predominant_rhythm
    key_signature key_confidence key_correlations modulations modulation_count
    chord_symbols harmonic_rhythm interval_distribution largest_interval
    stepwise_motion_ratio melodic_contour melodic_complexity
    form_analysis sections_count repeats_count cadence_types final_cadence
    clefs_used has_dynamics dynamic_range has_articulations has_ornaments
    has_tempo_changes has_fermatas expression_markings
    has_extracted_lyrics syllable_count lyrics_language
    part_names detected_instruments instrument_families
    is_vocal is_instrumental has_accompaniment
    texture_type polyphonic_density voice_independence
  ].freeze

  def extraction_debug_data(score)
    score.attributes.slice(*EXTRACTION_FIELDS).compact
  end

  private

  # Extract low/high from range hash (handles string or symbol keys)
  def extract_range(range_data)
    low = range_data["low"] || range_data[:low]
    high = range_data["high"] || range_data[:high]
    [low, high]
  end

  # Clamp value between 0 and 100
  def clamp(value)
    [[value, 0].max, 100].min
  end

  # Convert pitch name (e.g., "C4", "F#3") to MIDI note number
  def pitch_to_midi(pitch_name)
    return nil if pitch_name.blank?

    match = pitch_name.to_s.match(/^([A-Ga-g])([#b]?)(-?\d+)$/)
    return nil unless match

    note = match[1].upcase
    accidental = match[2]
    octave = match[3].to_i

    semitones = { "C" => 0, "D" => 2, "E" => 4, "F" => 5, "G" => 7, "A" => 9, "B" => 11 }
    offset = semitones[note]
    return nil unless offset

    offset += 1 if accidental == "#"
    offset -= 1 if accidental == "b"

    (octave + 1) * 12 + offset
  end
end
