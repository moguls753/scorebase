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
    "score.period" => { char: "⌛" },
    "score.genre" => { char: "◈" },
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

  # ─────────────────────────────────────────────────────────────────
  # Value Translation Helpers
  # Translate database values to localized display labels
  # Falls back to original value if no translation exists
  # ─────────────────────────────────────────────────────────────────

  def translate_score_value(category, value)
    return nil if value.blank?
    # Normalize: "CC BY 3.0" -> "cc_by_3_0", "20th Century" -> "20th_century"
    key = value.to_s.downcase.strip.gsub(/[^a-z0-9]+/, "_").gsub(/^_|_$/, "")
    t("score_values.#{category}.#{key}", default: value)
  end

  def translate_period(value)
    translate_score_value(:period, value)
  end

  def translate_genre(value)
    translate_score_value(:genre, value)
  end

  def translate_texture(value)
    translate_score_value(:texture, value)
  end

  def translate_language(value)
    translate_score_value(:language, value)
  end

  def translate_license(value)
    translate_score_value(:license, value)
  end

  def translate_difficulty_label(level)
    return nil unless level.to_i.between?(1, 5)
    label = DIFFICULTY_LABELS[level.to_i]
    t("score_values.difficulty.#{label}", default: label)
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
    # Pad odd-count sections to avoid empty grid cells
    if musical.any? && catalog.any?
      musical << { filler: true } if musical.size.odd?
      catalog << { filler: true } if catalog.size.odd?
      musical + [{ divider: true }] + catalog
    else
      musical + catalog
    end
  end

  # Musical/analysis facts (primary)
  def build_musical_facts(score)
    facts = []

    # Period - linkable (discover scores from the same era)
    if score.period.present?
      facts << fact_entry("score.period", translate_period(score.period), link: scores_path(period: score.period))
    end

    # Genre - linkable (primary genre if multiple exist)
    if (primary_genre = score.genre_list.first)
      facts << fact_entry("score.genre", translate_genre(primary_genre), link: scores_path(genre: primary_genre))
    end

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

    # Difficulty - visual meter (melodic_complexity preferred, legacy complexity as fallback)
    if (level = score_difficulty_level(score))
      facts << fact_entry("score.difficulty", nil, difficulty: level)
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
      facts << fact_entry("score.language", translate_language(score.language), link: scores_path(language: score.language))
    end

    # Non-linkable facts
    facts << { label: t("score.measures"), value: positive_or_nil(score.measure_count) }
    facts << { label: t("score.texture"), value: translate_texture(score.texture_type) }
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
    facts << { label: t("score.license"), value: translate_license(score.license) }
    facts.select { |f| f[:value].present? }
  end

  # ─────────────────────────────────────────────────────────────────
  # Difficulty Meter Component
  # Visual 5-block scale: beginner → easy → intermediate → advanced → expert
  # ─────────────────────────────────────────────────────────────────

  DIFFICULTY_LABELS = {
    1 => "beginner", 2 => "easy", 3 => "intermediate", 4 => "advanced", 5 => "expert"
  }.freeze

  def difficulty_meter(level)
    level = level.to_i
    return nil unless level.between?(1, 5)

    label = translate_difficulty_label(level)

    content_tag(:div, class: "difficulty-meter", aria: { label: "#{t('score.difficulty')}: #{label}" }) do
      blocks = (1..5).map do |i|
        content_tag(:span, "", class: "difficulty-block #{'is-filled' if i <= level}".strip)
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

  # Check if score has pitch range data worth showing
  def has_pitch_ranges?(score)
    score.pitch_range_per_part.present?
  end

  # ─────────────────────────────────────────────────────────────────
  # Pitch Range Helpers
  # ─────────────────────────────────────────────────────────────────

  # MIDI reference range for visualization (C2 to C6 = common musical range)
  MIDI_RANGE_MIN = 36  # C2
  MIDI_RANGE_MAX = 84  # C6

  # Format pitch range from hash: "C3 – G5"
  def format_part_range(range_data)
    low, high = extract_range(range_data)
    format_pitch_range(low, high)
  end

  # Calculate CSS style for pitch range bar visualization
  def pitch_range_bar_style(range_data)
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

  # ─────────────────────────────────────────────────────────────────
  # JSON-LD Structured Data
  # ─────────────────────────────────────────────────────────────────

  # Generate JSON-LD structured data for a music composition
  # Returns HTML-safe JSON (safe because .to_json escapes all user input for JSON context)
  def score_json_ld(score)
    data = {
      "@context" => "https://schema.org",
      "@type" => "MusicComposition",
      "name" => score.title,
      "url" => request.original_url,
      "isAccessibleForFree" => true,
      "inLanguage" => score.language.presence || "en",
      "provider" => {
        "@type" => "Organization",
        "name" => "ScoreBase",
        "url" => request.base_url
      }
    }

    # Composer
    data["composer"] = {
      "@type" => "Person",
      "name" => score.composer
    } if score.composer.present?

    # Description
    data["description"] = score.description.truncate(160) if score.description.present?

    # Genre (array including period for broader discovery)
    # Musicians search "Baroque motet" or "Romantic piano"
    genres = score.genre_list.dup
    genres << score.period if score.period.present? && !genres.include?(score.period)
    data["genre"] = genres if genres.any?

    # Music arrangement (voicing/instrumentation for discovery)
    # Critical for searches like "SATB choir" or "piano solo"
    arrangement = [score.voicing, score.instruments].compact.join(", ")
    data["musicArrangement"] = arrangement if arrangement.present?

    # Musical key
    data["musicalKey"] = score.primary_key_signature if score.key_signature.present?

    # Time signature
    data["timeRequired"] = format_duration_iso8601(score.duration_seconds) if score.duration_seconds.to_f > 0

    # Number of pages
    data["numberOfPages"] = score.page_count if score.page_count.to_i > 0

    # Date published (for SEO freshness signals)
    data["datePublished"] = score.posted_date.iso8601 if score.posted_date.present?

    # License (critical for public domain music)
    data["license"] = score.license if score.license.present?

    # Editor/arranger
    data["contributor"] = {
      "@type" => "Person",
      "name" => score.editor
    } if score.editor.present?

    # Lyrics
    if score.lyrics.present?
      data["lyrics"] = {
        "@type" => "CreativeWork",
        "text" => score.lyrics.truncate(500),
        "inLanguage" => score.lyrics_language || score.language || "en"
      }
    end

    # PDF encoding
    if score.has_pdf?
      data["encoding"] = {
        "@type" => "MediaObject",
        "encodingFormat" => "application/pdf",
        "contentUrl" => "#{request.base_url}#{file_score_path(score, 'pdf')}"
      }
    end

    # Safe because .to_json properly escapes all strings for JSON context
    data.to_json.html_safe
  end

  private

  # Format duration in seconds to ISO 8601 duration format (PT3M30S)
  # Required format for schema.org timeRequired property
  def format_duration_iso8601(seconds)
    return nil if seconds.blank? || seconds <= 0

    minutes = (seconds / 60).floor
    remaining_seconds = (seconds % 60).round

    if minutes > 0 && remaining_seconds > 0
      "PT#{minutes}M#{remaining_seconds}S"
    elsif minutes > 0
      "PT#{minutes}M"
    else
      "PT#{remaining_seconds}S"
    end
  end

  # Get difficulty level (1-5) from score
  # Priority: computed_difficulty > melodic_complexity > legacy complexity
  def score_difficulty_level(score)
    # Prefer new computed_difficulty (uses ALL metrics)
    if score.computed_difficulty.present?
      score.computed_difficulty.to_i.clamp(1, 5)
    # Fallback to melodic_complexity
    elsif score.melodic_complexity.present?
      mc = score.melodic_complexity.to_f
      if    mc < 0.2 then 1
      elsif mc < 0.4 then 2
      elsif mc < 0.6 then 3
      elsif mc < 0.8 then 4
      else                5
      end
    # Final fallback to PDMX legacy complexity
    elsif score.complexity.to_i.positive?
      score.complexity.to_i.clamp(1, 5)
    end
  end

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
