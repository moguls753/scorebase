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

  # ─────────────────────────────────────────────────────────────────
  # Unified Score Facts Grid
  # Merges musical + catalog metadata into one cohesive block
  # ─────────────────────────────────────────────────────────────────

  # Icons for musical facts - helps scanning
  # Using reliable Unicode ranges (U+2000s) - avoid Musical Symbols block (U+1D100s)
  # Some glyphs need alignment nudges due to font baseline quirks
  FACT_ICONS = {
    "score.key" => { char: "♯" },
    "score.time" => { char: "⁄" },
    "score.voicing" => { char: "♬" },
    "score.range" => { char: "↕" },
    "score.tempo" => { char: "♩" },
    "score.duration" => { char: "◷", css: "score-fact-icon--nudge-1" },
    "score.difficulty" => { char: "◆", css: "score-fact-icon--nudge-2" },
    "score.language" => { char: "¶" }
  }.freeze

  def fact_icon(key)
    FACT_ICONS.dig(key, :char)
  end

  def fact_icon_css(key)
    FACT_ICONS.dig(key, :css)
  end

  # Build a fact entry hash with icon data
  def fact_entry(key, value, link: nil, difficulty: nil, css: nil)
    {
      label: t(key),
      value: value,
      icon: fact_icon(key),
      icon_css: fact_icon_css(key),
      link: link,
      difficulty: difficulty,
      css: css
    }.compact
  end

  # Returns unified array of all score facts for grid display
  # Each fact: { label:, value:, icon:, link:, css:, difficulty: }
  def unified_score_facts(score)
    musical = build_musical_facts(score)
    catalog = build_catalog_facts(score)

    # Add divider if both sections have content
    if musical.any? && catalog.any?
      musical + [{ divider: true }] + catalog
    else
      musical + catalog
    end
  end

  # Musical/analysis facts (primary)
  def build_musical_facts(score)
    facts = []

    # Key signature - descriptive, not linkable (too broad for discovery)
    if score.key_signature.present?
      facts << fact_entry("score.key", score.key_signature)
    end

    # Time signature - descriptive, not linkable (4/4 = half the catalog)
    if score.time_signature.present?
      facts << fact_entry("score.time", score.time_signature)
    end

    # Voicing - linkable
    if score.voicing.present?
      facts << fact_entry("score.voicing", score.voicing, link: scores_path(voicing: score.voicing))
    end

    # Difficulty - special display (meter)
    if score.complexity.to_i.positive?
      facts << fact_entry("score.difficulty", nil, difficulty: score.complexity.to_i)
    end

    # Pitch range
    range = format_pitch_range(score.lowest_pitch, score.highest_pitch)
    facts << fact_entry("score.range", range) if range

    # Tempo
    tempo = format_tempo(score.tempo_marking, score.tempo_bpm)
    facts << fact_entry("score.tempo", tempo) if tempo

    # Duration
    duration = format_duration(score.duration_seconds)
    facts << fact_entry("score.duration", duration) if duration

    # Language - linkable
    if score.language.present?
      facts << fact_entry("score.language", score.language, link: scores_path(language: score.language))
    end

    # Non-linkable facts
    facts << { label: t("score.measures"), value: positive_or_nil(score.measure_count) }
    facts << { label: t("score.texture"), value: score.texture_type&.capitalize }
    facts << { label: t("score.parts"), value: positive_or_nil(score.num_parts) }
    facts << { label: t("score.instruments"), value: score.instruments }
    facts << { label: t("score.page_count"), value: positive_or_nil(score.page_count) }

    facts.select { |f| f[:value].present? || f[:difficulty].present? }
  end

  # Catalog/source facts (secondary - CPDL, IMSLP metadata)
  def build_catalog_facts(score)
    facts = []
    facts << { label: t("score.cpdl_number"), value: score.cpdl_number, css: "font-mono" }
    facts << { label: t("score.editor"), value: score.editor }
    facts << { label: t("score.posted_date"), value: score.posted_date }
    facts << { label: t("score.license"), value: score.license }
    facts.select { |f| f[:value].present? }
  end

  # ─────────────────────────────────────────────────────────────────
  # Difficulty Meter Component
  # Visual 3-block scale instead of "2/3" text
  # ─────────────────────────────────────────────────────────────────

  DIFFICULTY_LABELS = { 1 => "easy", 2 => "medium", 3 => "hard" }.freeze

  def difficulty_meter(level)
    return nil unless level.to_i.positive? && level.to_i <= 3

    level = level.to_i
    label = DIFFICULTY_LABELS[level]

    content_tag(:div, class: "difficulty-meter", aria: { label: "#{t('score.difficulty')}: #{level}/3" }, title: label&.capitalize) do
      blocks = (1..3).map do |i|
        classes = ["difficulty-block"]
        classes << "is-filled" if i <= level
        content_tag(:span, "", class: classes.join(" "))
      end
      safe_join(blocks) + content_tag(:span, label, class: "difficulty-label")
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

  # Format tempo: "Andante (72)" or just "72"
  # Icon prefix handles the musical context — value is pure data
  def format_tempo(marking, bpm)
    return nil if marking.blank? && bpm.blank?

    if marking.present? && bpm.present?
      "#{marking} (#{bpm})"
    elsif marking.present?
      marking
    else
      bpm.to_s
    end
  end

  # Format pitch range: "C3 – G5"
  def format_pitch_range(low, high)
    return nil if low.blank? || high.blank?
    "#{low} – #{high}"
  end

  def has_extracted_data?(score)
    score.extraction_extracted?
  end

  # Check if score has vocal range data worth showing
  def has_vocal_ranges?(score)
    score.pitch_range_per_part.present? && score.pitch_range_per_part.keys.length > 1
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
    format_pitch_range(low, high)
  end

  # Calculate CSS style for vocal range bar visualization
  def vocal_range_bar_style(range_data)
    low, high = extract_range(range_data)
    return "" if low.blank? || high.blank?

    low_midi = pitch_to_midi(low)
    high_midi = pitch_to_midi(high)
    return "" if low_midi.nil? || high_midi.nil?

    range_span = MIDI_RANGE_MAX - MIDI_RANGE_MIN
    left_pct = ((low_midi - MIDI_RANGE_MIN).to_f / range_span * 100).clamp(0, 100)
    right_pct = ((high_midi - MIDI_RANGE_MIN).to_f / range_span * 100).clamp(0, 100)
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

  # Return value only if positive, otherwise nil
  def positive_or_nil(value)
    value.to_i.positive? ? value : nil
  end

  # Extract low/high from range hash (handles string or symbol keys)
  def extract_range(range_data)
    low = range_data["low"] || range_data[:low]
    high = range_data["high"] || range_data[:high]
    [low, high]
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
