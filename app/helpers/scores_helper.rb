module ScoresHelper
  # All filter parameters (used for hidden fields to preserve state)
  # Core filters: instrument, difficulty, period, genre, length, voicing (parts), pricing
  # Contextual filters: voice_type, language (shown when vocal instrument selected)
  FILTER_PARAMS = %i[instrument difficulty period genre length voicing voice_type language pricing].freeze

  # Superset of every filter/search param the scores list and the hub listings accept.
  PAGINATION_PARAMS = (FILTER_PARAMS + %i[source key time q sort composer]).freeze

  # Count active filters from params
  def active_filters_count
    FILTER_PARAMS.count { |param| params[param].present? }
  end

  # Generate hidden fields for all filter params to preserve state across forms
  def filter_hidden_fields(form)
    safe_join(FILTER_PARAMS.map { |param| form.hidden_field(param, value: params[param]) })
  end

  # source/key/time are searching? triggers but not in FILTER_PARAMS
  def search_trigger_hidden_fields(form)
    safe_join(%i[source key time].filter_map { |p| form.hidden_field(p, value: params[p]) if params[p].present? })
  end

  # when nothing survives this resolves to the frameless landing (the frame-missing net promotes it)
  def clear_filters_path
    scores_path(**{ q: params[:q], source: params[:source], key: params[:key], time: params[:time] }.compact_blank)
  end

  # clean screen-reader phrasing (visible "128 / 441,026" is read as "slash")
  def results_announce_text
    return t("hub.no_scores_found") if @filtered_count.to_i.zero?
    "#{number_with_delimiter(@filtered_count)} #{t('search.results_count')}"
  end

  # Instrument options for filter dropdown
  # Ordered by match count in database. Only specific instruments, no categories.
  # Voice/Choir triggers contextual vocal filters (voice_type, language)
  #
  # Match counts (via LIKE query):
  #   voice/cappella: 43k+  |  violin: 6,197  |  flute: 2,680
  #   piano: 29,576         |  cello: 3,312   |  guitar: 2,273
  #   organ: 7,770          |
  def instrument_filter_options
    [
      [t("filters.any"), ""],
      [t("instruments.voice_choir"), "voice"],
      [t("instruments.piano"), "piano"],
      [t("instruments.organ"), "organ"],
      [t("instruments.violin"), "violin"],
      [t("instruments.cello"), "cello"],
      [t("instruments.flute"), "flute"],
      [t("instruments.guitar"), "guitar"]
    ]
  end

  # ─────────────────────────────────────────────────────────────────
  # SMD (Sheet Music Direct) Helpers
  # ─────────────────────────────────────────────────────────────────

  # Format USD price for display
  # Shows dollar price globally - SMD converts to local currency on their site
  def format_smd_price(score)
    return nil if score.price_usd.blank? || score.price_usd.to_f <= 0
    "$#{'%.2f' % score.price_usd}"
  end

  # Buy CTA label: price-qualified when known, plain "view" otherwise.
  def smd_cta_label(score)
    price = format_smd_price(score)
    price ? t("score.buy_on_smd", price: price) : t("score.view_on_smd")
  end

  # Check if score has a sale price (original > current)
  def smd_on_sale?(score)
    score.original_price_usd.present? &&
      score.price_usd.present? &&
      score.original_price_usd > score.price_usd
  end

  # Format price with optional sale display
  # Returns nil or { current:, original?: } hash
  def format_smd_price_with_sale(score)
    current = format_smd_price(score)
    return nil unless current

    if smd_on_sale?(score)
      { current: current, original: "$#{'%.2f' % score.original_price_usd}" }
    else
      { current: current }
    end
  end

  # Badge data for score card thumbnails
  # Returns { type: :commercial, text: "$" } for paid scores, nil for free
  # Free scores have no badge - absence of badge implies free
  def score_card_badge(score)
    return nil unless format_smd_price(score)
    { type: :commercial, text: "$" }
  end

  # ─────────────────────────────────────────────────────────────────
  # SEO Meta Description for Score Pages
  # ─────────────────────────────────────────────────────────────────

  # SEO-friendly genre labels for SMD scores
  # Maps SMD tag patterns to user-friendly descriptions
  SMD_GENRE_LABELS = {
    "Video Game" => "Video Game",
    "Film/TV" => "Film/TV",
    "Broadway" => "Broadway",
    "Musical/Show" => "Musical",
    "Disney" => "Disney",
    "Anime" => "Anime",
    "Christmas" => "Christmas",
    "Wedding" => "Wedding",
    "Klassik" => "Classical"
  }.freeze

  # Buy-intent <title> for SMD category pages; unchanged plain form otherwise.
  def score_page_title(score)
    if score.smd? && score.smd_category.present?
      "#{score.title} for #{score.smd_category} — Sheet Music"
    else
      title = score.display_title
      title += " - #{score.composer}" if score.composer.present?
      title
    end
  end

  # Generate SEO-optimized meta description for a score page
  # Target: under 155 chars, includes searchable attributes
  # Example: "Moonlight Sonata by Beethoven — C# minor, Piano, Intermediate. Free PDF sheet music."
  # SMD: "Ezio's Family (from Assassin's Creed II) — Piano, Video Game. Sheet music available."
  def score_meta_description(score)
    parts = []

    # Title and composer (required)
    if score.composer.present?
      parts << "#{score.display_title} by #{score.composer}"
    else
      parts << score.display_title
    end

    # Musical attributes (key, instruments, difficulty, genre for SMD)
    attrs = []
    attrs << score.key_signature if score.key_signature.present?
    attrs << score.instruments if score.instruments.present?

    if (level = score_difficulty_level(score))
      attrs << translate_difficulty_label(level)
    end

    # Add SMD ensemble category (Jazz Ensemble, Concert Band, etc.);
    # skip when it merely repeats the instruments string already added.
    if score.smd? && score.smd_category.present? && !attrs.include?(score.smd_category)
      attrs << score.smd_category
    end

    # Add genre context for SMD (Video Game, Film/TV, Broadway, etc.)
    if score.smd? && score.tags.present?
      genre_label = extract_smd_genre_label(score.tags)
      attrs << genre_label if genre_label
    end

    # Add page count for SMD (useful info)
    attrs << "#{score.page_count} pages" if score.smd? && score.page_count.to_i > 0

    parts << attrs.join(", ") if attrs.any?

    # Value proposition (different for commercial vs free)
    parts << (score.smd? ? t("meta.score_cta_smd") : t("meta.score_cta"))

    # Join and truncate to 155 chars
    description = parts.join(" — ")
    description.truncate(155)
  end

  # ─────────────────────────────────────────────────────────────────
  # Score Show Page Helpers
  # ─────────────────────────────────────────────────────────────────

  # Normalize source for display and CSS class
  # openscore-lieder, openscore-quartets -> openscore
  def normalize_source(source)
    return nil if source.blank?
    source.start_with?("openscore") ? "openscore" : source
  end

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
    "score.language" => { char: "¶" },
    "score.ensemble" => { char: "⁂" }
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
  def fact_entry(key, value, link: nil, difficulty: nil, grade: nil, css: nil)
    {
      label: t(key),
      value: value,
      icon: fact_icon(key),
      icon_css: fact_icon_css(key),
      link: link,
      difficulty: difficulty,
      grade: grade,
      css: css
    }.compact
  end

  # Returns unified array of all score facts for grid display
  # Each fact: { label:, value:, icon:, link:, css:, difficulty: }
  def unified_score_facts(score)
    musical = build_musical_facts(score)
    catalog = build_catalog_facts(score)

    # Add divider if both sections have content
    # CSS handles odd items with grid-column: 1 / -1 (full width)
    if musical.any? && catalog.any?
      musical + [{ divider: true }] + catalog
    else
      musical + catalog
    end
  end

  # Musical/analysis facts (primary)
  def build_musical_facts(score)
    facts = []

    # Period - linkable (discover scores from the same era). No fallback: by_period
    # returns nothing for any value that has no hub, so a filter link would be dead.
    if score.period.present?
      facts << fact_entry("score.period", translate_period(score.period),
                          link: hub_path_for(:periods, canonical_period(score.period)))
    end

    if (ensemble = smd_ensemble_fact(score))
      facts << ensemble
    end

    # Genre - linkable (primary genre if multiple exist). The filter fallback only
    # returns rows for a normalized genre, which is also what by_genre requires.
    if (primary_genre = score.genre_list.first)
      fallback = scores_path(genre: primary_genre) if score.genre_status == "normalized"
      facts << fact_entry("score.genre", translate_genre(primary_genre),
                          link: hub_path_for(:genres, primary_genre) || fallback)
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

    # Difficulty - visual meter with optional ABRSM grade for teachers
    if (level = score_difficulty_level(score))
      # Use localized grade with fallback: German "Oberstufe" or English "Grade 7-8"
      grade = localized_pedagogical_grade(score)
      facts << fact_entry("score.difficulty", nil, difficulty: level, grade: grade)
    end

    # Pitch range - MusicXML extraction OR SMD metadata fallback
    range = format_pitch_range(score.lowest_pitch, score.highest_pitch)
    range ||= score.pitch_range if score.smd? && score.pitch_range.present?
    facts << fact_entry("score.range", range) if range

    # Tempo
    tempo = format_tempo(score.tempo_marking, score.tempo_bpm)
    facts << fact_entry("score.tempo", tempo) if tempo

    # Duration (uses effective_duration to include estimated durations)
    duration = format_duration(score.effective_duration)
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

  # Catalog/source facts (secondary - CPDL, IMSLP, SMD metadata)
  def build_catalog_facts(score)
    facts = []

    # Source-specific facts
    facts.concat(smd_catalog_facts(score)) if score.smd?

    # Common catalog fields
    facts << { label: t("score.cpdl_number"), value: score.cpdl_number, css: "font-mono" }
    facts << { label: t("score.editor"), value: score.editor }
    facts << { label: t("score.posted_date"), value: score.posted_date }
    facts << { label: t("score.license"), value: translate_license(score.license) }
    facts.select { |f| f[:value].present? || f[:price].present? }
  end

  # SMD-specific catalog facts - consolidated for maintainability
  def smd_catalog_facts(score)
    [
      smd_price_fact(score),
      { label: t("score.rating"), value: format_smd_rating(score) },
      { label: t("score.brand"), value: score.brand },
      smd_arrangement_fact(score),
      smd_interactive_fact(score)
    ].compact
  end

  # Price fact - always uses :price key with { current:, original?: } hash
  def smd_price_fact(score)
    price_data = format_smd_price_with_sale(score)
    return nil unless price_data

    { label: t("score.price"), price: price_data }
  end

  # The ensemble hub is otherwise reachable only via /ensembles, which left the
  # larger hubs uncrawled — this is their internal-link surface.
  def smd_ensemble_fact(score)
    hub = ensemble_hub_for(score)
    return nil unless hub

    fact_entry("score.ensemble", translate_hub_name(:ensembles, hub),
               link: ensemble_path(slug: hub[:slug]))
  end

  # The /scores filter these replace is noindex, so it can never rank and the link
  # is spent on a dead end.
  HUB_PATHS = { periods: :period_path, genres: :genre_path }.freeze

  def hub_path_for(type, name)
    hub = hub_item_for(type, name)
    hub && public_send(HUB_PATHS.fetch(type), slug: hub[:slug])
  end

  def hub_item_for(type, name)
    return nil if name.blank?

    HubDataBuilder.public_send(type).find { |item| item[:name] == name }
  end

  # Scores carry LLM output variants ("Contemporary", "20th Century"); hubs and the
  # by_period scope are both keyed on the canonical era, so an unmapped variant
  # resolves to nothing at all rather than to the wrong era.
  def canonical_period(name)
    return nil if name.blank?

    HubDataBuilder::PERIODS.find { |_, variants| variants.include?(name) }&.first
  end

  # arrangement_category is a strict coarsening of the ensemble ("Concert Band"
  # -> "Band"), so it only earns its own cell where no ensemble hub applies.
  def smd_arrangement_fact(score)
    return nil if ensemble_hub_for(score)

    { label: t("score.arrangement"), value: score.arrangement_category }
  end

  # Resolved against the built hubs, not the allowlist: a category below
  # THRESHOLD has no page, and linking it would 404.
  def ensemble_hub_for(score)
    hub_item_for(:ensembles, score.smd_category)
  end

  # Interactive badge - shown when SMD score has playback features
  def smd_interactive_fact(score)
    return nil unless score.is_interactive?
    { label: t("score.interactive"), value: "✓", css: "score-fact-badge" }
  end

  # Format SMD rating with stars: "★ 4.5 (12)"
  def format_smd_rating(score)
    return nil unless score.rating.to_f.positive?
    rating = "★ #{'%.1f' % score.rating}"
    rating += " (#{score.review_count})" if score.review_count.to_i.positive?
    rating
  end

  # ─────────────────────────────────────────────────────────────────
  # Difficulty Meter Component
  # Visual 5-block scale: beginner → elementary → intermediate → advanced → expert
  # Matches filter labels and pedagogical terminology
  # ─────────────────────────────────────────────────────────────────

  DIFFICULTY_LABELS = {
    1 => "beginner", 2 => "elementary", 3 => "intermediate", 4 => "advanced", 5 => "expert"
  }.freeze

  # Inverse mapping: "Grade 7-8" -> 5 (expert)
  # Built from Score::DIFFICULTY_LEVELS for consistency with filter
  GRADE_TO_LEVEL = Score::DIFFICULTY_LEVELS.flat_map { |name, grades|
    level = { "beginner" => 1, "elementary" => 2, "intermediate" => 3, "advanced" => 4, "expert" => 5 }[name]
    grades.map { |g| [g, level] }
  }.to_h.freeze

  def difficulty_meter(level, grade: nil)
    level = level.to_i
    return nil unless level.between?(1, 5)

    label = translate_difficulty_label(level)
    aria_label = grade.present? ? "#{label} (#{grade})" : label

    content_tag(:div, class: "difficulty-meter", aria: { label: "#{t('score.difficulty')}: #{aria_label}" }) do
      blocks = (1..5).map do |i|
        content_tag(:span, "", class: "difficulty-block #{'is-filled' if i <= level}".strip)
      end
      # Grade in mixed-case for readability: "EXPERT (Grade 7-8)"
      label_html = if grade.present?
        "#{label} ".html_safe + content_tag(:span, "(#{grade})", class: "difficulty-grade")
      else
        label
      end
      safe_join(blocks) + content_tag(:span, label_html, class: "difficulty-label")
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

  # Format pitch range with locale-aware notation
  # English: "C3 – G5" (Scientific)
  # German:  "c – g''" (Helmholtz)
  def format_pitch_range(low, high)
    return nil if low.blank? || high.blank?

    if I18n.locale == :de
      "#{to_helmholtz(low)} – #{to_helmholtz(high)}"
    else
      "#{low} – #{high}"
    end
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
    event_count pitch_count note_density unique_pitches accidental_count chromatic_ratio
    rhythm_distribution syncopation_level rhythmic_variety predominant_rhythm
    key_signature key_confidence key_correlations modulations modulation_count
    chord_count unique_chord_count harmonic_rhythm interval_distribution largest_interval
    stepwise_motion_ratio melodic_contour melodic_complexity
    form_analysis sections_count repeats_count cadence_types final_cadence
    clefs_used has_dynamics dynamic_range has_articulations has_ornaments
    has_tempo_changes has_fermatas expression_markings
    has_extracted_lyrics syllable_count lyrics_language
    part_names detected_instruments instrument_families
    has_vocal is_instrumental has_accompaniment
    simultaneous_note_avg texture_variation avg_chord_span
    contrary_motion_ratio parallel_motion_ratio oblique_motion_ratio
    texture_type vertical_density voice_independence
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
    # Commercial SMD pages are Products carrying a price Offer (earns price rich
    # results for buy-intent searches); free scores stay public-domain
    # MusicCompositions. The Offer names SMD as seller (ScoreBase is an affiliate,
    # not the merchant). Never emit review/aggregateRating — SMD's ratings aren't
    # ScoreBase's own, and passing them off risks a site-wide structured-data penalty.
    commercial = score.smd? && score.price_usd.to_f.positive?

    data = {
      "@context" => "https://schema.org",
      "@type" => commercial ? "Product" : "MusicComposition",
      "name" => score.title,
      "url" => request.original_url,
      "inLanguage" => score.language.presence || "en",
      "provider" => {
        "@type" => "Organization",
        "name" => "ScoreBase",
        "url" => request.base_url
      }
    }
    data["isAccessibleForFree"] = true unless commercial

    if commercial
      data["image"] = score.thumbnail if score.thumbnail.present?
      data["brand"] = { "@type" => "Brand", "name" => score.brand } if score.brand.present?
      data["offers"] = {
        "@type" => "Offer",
        "price" => format("%.2f", score.price_usd),
        "priceCurrency" => "USD",
        "availability" => "https://schema.org/InStock",
        "url" => request.original_url,
        "seller" => { "@type" => "Organization", "name" => "Sheet Music Direct" }
      }
    end

    # Composer
    data["composer"] = {
      "@type" => "Person",
      "name" => score.composer
    } if score.composer.present?

    # Description
    if score.description.present?
      data["description"] = score.description.truncate(160)
    elsif commercial
      data["description"] = score_meta_description(score)
    end

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
    data["timeRequired"] = format_duration_iso8601(score.effective_duration) if score.effective_duration.to_f > 0

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

  # BreadcrumbList JSON-LD: Home → parent hub → this score. The parent hub is the
  # composer/artist collection page (SMD prefers the artist hub when present).
  # Uses route _url helpers so it is testable in helper specs (no request object)
  # and locale-correct via default_url_options.
  def breadcrumb_json_ld(score)
    items = [
      breadcrumb_item(1, t("nav.home"), root_url)
    ]

    hub = breadcrumb_parent_hub(score)
    items << breadcrumb_item(items.size + 1, hub[:name], hub[:url]) if hub

    items << breadcrumb_item(items.size + 1, score.title, score_url(id: score.id))

    {
      "@context" => "https://schema.org",
      "@type" => "BreadcrumbList",
      "itemListElement" => items
    }.to_json.html_safe
  end

  private

  def breadcrumb_item(position, name, url)
    {
      "@type" => "ListItem",
      "position" => position,
      "name" => name,
      "item" => url
    }
  end

  # SMD scores hang off the artist hub (falls back to composer); free scores off
  # the composer hub. Returns nil when no hub name applies (no exception on nil).
  # Only emit a parent crumb when the hub actually exists (>= THRESHOLD scores);
  # otherwise the BreadcrumbList would point at a 404. find_by_slug is cache-backed.
  def breadcrumb_parent_hub(score)
    if score.smd? && score.artist.present?
      slug = score.artist.parameterize
      name = HubDataBuilder.find_by_slug(:artists, slug)
      return { name: name, url: artist_url(slug: slug) } if name
    end
    if score.composer.present?
      slug = score.composer.parameterize
      name = HubDataBuilder.find_by_slug(:composers, slug)
      return { name: name, url: composer_url(slug: slug) } if name
    end
    nil
  end

  # Extract user-friendly genre label from SMD tags
  # Tags are hyphen-delimited: "Pop-Video Game-Rock" → "Video Game"
  # Returns first matching high-value genre or nil
  def extract_smd_genre_label(tags)
    return nil if tags.blank?

    SMD_GENRE_LABELS.each do |pattern, label|
      return label if tags.include?(pattern)
    end

    nil
  end

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
  # Priority: pedagogical_grade (matches filter) > computed_difficulty > melodic_complexity > legacy
  def score_difficulty_level(score)
    # Prefer pedagogical_grade (LLM-assigned, matches filter logic)
    if score.pedagogical_grade.present? && GRADE_TO_LEVEL[score.pedagogical_grade]
      GRADE_TO_LEVEL[score.pedagogical_grade]
    # Fallback to computed_difficulty (algorithmic)
    elsif score.computed_difficulty.present?
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

  # Get localized pedagogical grade with fallback
  # German: "Oberstufe", English: "Grade 7-8"
  def localized_pedagogical_grade(score)
    case I18n.locale
    when :de
      score.pedagogical_grade_de.presence || score.pedagogical_grade.presence
    else
      score.pedagogical_grade.presence
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

  # Scientific pitch to Helmholtz notation
  # C2 -> C, C3 -> c, C4 -> c', C5 -> c'', G5 -> g''
  def to_helmholtz(pitch)
    return pitch if pitch.blank?

    match = pitch.to_s.match(/^([A-Ga-g])([#b]?)(-?\d+)$/)
    return pitch unless match

    note, accidental, octave = match[1], match[2], match[3].to_i

    case octave
    when 0 then "#{note.upcase}#{accidental},,"
    when 1 then "#{note.upcase}#{accidental},"
    when 2 then "#{note.upcase}#{accidental}"
    when 3 then "#{note.downcase}#{accidental}"
    when 4 then "#{note.downcase}#{accidental}'"
    when 5 then "#{note.downcase}#{accidental}''"
    when 6 then "#{note.downcase}#{accidental}'''"
    when 7 then "#{note.downcase}#{accidental}''''"
    else pitch
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Grouped Parts Helpers (SMD Ensemble Arrangements)
  # ─────────────────────────────────────────────────────────────────

  # Instrument family patterns for grouping parts
  # Order matters: more specific patterns first
  INSTRUMENT_FAMILIES = {
    "Score" => /^(full|conductor|score)/i,
    "Brass" => /trumpet|trombone|horn|tuba|euphonium|cornet|flugelhorn|baritone(?! sax)/i,
    "Woodwinds" => /flute|clarinet|oboe|bassoon|sax|piccolo|recorder/i,
    "Strings" => /violin|viola|cello|bass(?! clar)|harp|string|fiddle/i,
    "Percussion" => /percussion|drums?|timpani|mallet|vibes|bell|chime|xylophone|marimba|glock|conga|bongo|tambourine|triangle|cymbal|snare|tom|shaker|cabasa/i,
    "Keys" => /piano|keyboard|organ|synth|celesta/i,
    "Guitar" => /guitar|banjo|mandolin|ukulele|dobro/i,
    "Vocal" => /voice|vocal|soprano|alto|tenor|choir|chorus|satb|ssab|ssaa|sab|ssa|ttbb|tb\b/i
  }.freeze

  FAMILY_ORDER = %w[Score Brass Woodwinds Strings Percussion Keys Guitar Vocal Other].freeze

  # Determine instrument family from part name
  def instrument_family(part_name)
    return "Other" if part_name.blank?

    INSTRUMENT_FAMILIES.each do |family, pattern|
      return family if part_name.match?(pattern)
    end

    "Other"
  end

  # Group parts by instrument family
  # Returns hash: { "Brass" => [score1, score2], "Woodwinds" => [...] }
  def group_parts_by_family(parts)
    grouped = parts.group_by { |part| instrument_family(part.part_name) }

    # Sort by family order
    FAMILY_ORDER.each_with_object({}) do |family, result|
      result[family] = grouped[family] if grouped[family].present?
    end
  end

  # Threshold for showing grouped vs flat list
  PARTS_GROUPING_THRESHOLD = 8

  # Should parts be grouped by family?
  def should_group_parts?(parts_count)
    parts_count > PARTS_GROUPING_THRESHOLD
  end
end
