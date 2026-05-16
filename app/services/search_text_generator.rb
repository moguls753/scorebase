# frozen_string_literal: true

# Generates searchable descriptions for RAG indexing.
# Uses LLM to write rich, searchable text from score metadata.
#
# Usage:
#   result = SearchTextGenerator.new.generate(score)
#   result.description  # => "Easy beginner piano piece..."
#   result.success?     # => true
#   result.issues       # => [] (empty if valid)
#
class SearchTextGenerator
  # Academic metric-compounds that no one searches for.
  # Individual terms like "chromatic", "polyphonic", "syncopation" are fine.
  JARGON_TERMS = [
    "chromatic complexity",
    "vertical density",
    "melodic complexity",
    "pitch palette",
    "rhythmic variety"
  ].freeze

  # Composer values that should be omitted from search text.
  # These scores still have valuable metadata, just no known composer.
  COMPOSER_PLACEHOLDERS = %w[
    NA N/A Unknown Anon Anon. Anonymous
    Traditional Trad Trad. Tradicional
  ].freeze

  # Movement/section names that improve search recall.
  # User searching "sarabande" should find suites containing sarabandes.
  MOVEMENT_NAMES = %w[
    allemande courante sarabande gigue menuet menuetto minuet gavotte
    bourree bourrée prelude fugue praeludium fuga air trio
    rondo scherzo finale toccata passepied loure anglaise polonaise
    badinerie overture ouverture intermezzo siciliano sicilienne
    passacaglia chaconne fantasia ricercar invention sinfonia
  ].freeze

  Result = Data.define(:description, :issues, :error) do
    def success? = error.nil? && issues.empty?
  end

  RICH_PROMPT = <<~PROMPT
    <role>
    You write rich, searchable descriptions for a sheet music catalog used by music teachers, choir directors, church musicians, and university professors. Follow the <rules/> and the <steps/> to generate an answer. You can find some positive examples in the <examples/> section.
    </role>

    <rules>
    - Write 5–7 sentences (150-250 words) in a paragraph that gives a complete picture of the piece.
    - START with the title. If composer is provided, include it (e.g., "Étude Op.6 by Fernando Sor is..."). If no composer, start with just the title (e.g., "O Come All Ye Faithful is a beloved Christmas hymn...").
    - Include ALL of these elements:
      (1) TITLE (and COMPOSER if provided) in the first sentence
      (2) DIFFICULTY: Handle based on the format of difficulty_level:
          - If it starts with "Grade" (e.g., "Grade 4-5 (Mittelstufe I)"): This is a pedagogical grade. Use it naturally: "an intermediate piece (Grade 4-5)" or "suitable for Grade 4-5 students (Mittelstufe I)".
          - If it's a neutral phrase like "technically accessible" or "moderate technical demands": Use it as-is to describe the piece. Do NOT convert to "beginner" or "easy".
          - If is_virtuoso is true, say "virtuoso".
          - If difficulty_level is NOT provided, do NOT mention difficulty at all.
      (3) CHARACTER (2-3 mood/style words: gentle, dramatic, contemplative, energetic, majestic, lyrical, playful, solemn, etc.)
      (4) BEST FOR (specific uses: sight-reading practice, student recitals, church services, exam repertoire, technique building, competitions, teaching specific skills)
      (5) MUSICAL FEATURES (texture, harmonic language, notable patterns like arpeggios, scales, counterpoint)
      (6) KEY DETAILS (duration, instrumentation, key, period/style). If <data/> lists multiple instruments, NAME EVERY ONE in the description — do not collapse "Piano, Violin" to "a piano work" or describe a chamber piece by a single instrument.
      (7) SECTIONS: If "sections" field lists movement types (e.g., "allemande, courante, sarabande, gigue"), mention them - users search for these dance forms
    - Use words musicians actually search: "sight-reading", "recital piece", "exam repertoire", "church anthem", "teaching piece", "competition", "Baroque counterpoint", "lyrical melody", "chromatic passages", "syncopated rhythms".
    - NEVER use academic metric-compounds like "chromatic complexity", "vertical density", "melodic complexity", "rhythmic variety". The data uses searchable terms already - use them naturally in prose.
    - STRICT: Only mention instruments, voicing, genre, and other details that appear in <data/>. Do not invent or assume facts not present in the data. Conversely, do not omit instruments that ARE in the data — every instrument listed under "instruments" must appear by name in the description.
    - CRITICAL: If difficulty_level is missing from the data, you MUST NOT mention difficulty. If difficulty_level is a neutral phrase (not a Grade), do NOT convert it to "beginner" or "easy" - use the exact phrase provided.
    - Do not produce a bullet point list.
    </rules>

    <steps>
    1) Read the metadata: identify instrument, genre, key, time signature, texture, range, duration.
    2) If difficulty_level is provided, use it exactly as described in the rules. If not provided, skip mentioning difficulty entirely.
    3) Pick 2–3 CHARACTER words based on metadata cues (key, tempo, texture suggest mood).
    4) List 2–3 specific BEST FOR uses (teaching, performance, liturgical, exam, etc.).
    5) Note interesting MUSICAL FEATURES worth mentioning (counterpoint, ornamentation, range demands).
    6) Write 5–7 flowing sentences covering all elements above.
    </steps>

    <examples>
    - "Étude Op.6 No.1 by Fernando Sor is an intermediate guitar piece (Grade 4-5, Mittelstufe I) with a lyrical, singing character. The study develops right-hand arpeggiation while maintaining a clear melodic line in the upper voice. Excellent for students working toward Grade 5 exams or preparing for intermediate-level recitals. Features moderate position shifts and demands good finger independence. About 2 minutes long, ideal for technique building in the classical guitar curriculum."
    - "Ascendit Deus by Peter Philips is an advanced SATB anthem with a joyful, majestic character, well-suited for Easter services or festive choir concerts. The four-part writing features independent voice lines and some chromatic passages that require confident singers. Soprano part reaches B5, so ensure your section can handle the tessitura. The energetic rhythms and triumphant harmonies make this a rewarding showpiece. About 4 minutes long."
    - "Prelude in C minor by an unknown composer is a technically accessible keyboard piece with a contemplative, introspective character. The stepwise melodic motion and straightforward harmonies make it approachable for developing pianists. Useful for building comfort with minor keys and simple ornamentation. About 2 minutes long."
    - "Violin Sonata No. 1 by Johannes Brahms is a lyrical and deeply expressive violin sonata in the Romantic style. Features singing melodic lines with dynamic contrasts and rich piano accompaniment. Excellent choice for student recitals, conservatory auditions, or as exam repertoire. A substantial work around 25 minutes that develops musicality and interpretation skills." (Note: no difficulty_level was provided, so difficulty is not mentioned)
    - "O Come All Ye Faithful is a beloved intermediate Christmas hymn for SATB choir with organ accompaniment. The stately, joyful character makes it a staple of holiday church services and carol concerts. Features straightforward four-part harmony with some moving inner voices. The familiar melody is accessible for congregational singing while offering enough interest for trained choirs. About 3 minutes long, ideal for processionals or as a service closer."
    </examples>

    <data>
    %{metadata_json}
    </data>

    <output_format>
    Return valid JSON with this structure: {"description": "your description here"}
    </output_format>
  PROMPT

  SPARSE_PROMPT = <<~PROMPT
    <role>
    You write concise, searchable descriptions for sheet music whose detailed
    musical features (duration, syncopation, ornamentation, voice leading,
    range, complexity scores) are NOT in the data. You DO have catalog metadata:
    artist, publisher (brand), arrangement category, sub-category, and style
    tags. Translate that catalog vocabulary into natural search-friendly prose.
    Used by music teachers, choir directors, church musicians, and home learners.
    </role>

    <rules>
    - Write 4-6 sentences (40-70 words, roughly 200-350 characters). Density beats length.
    - FIRST sentence MUST include: title, artist or composer (if given), and arrangement type (guitar tab, easy piano arrangement, SATB choir, jazz ensemble, etc.). If the title contains "arr. NAME", mention the arranger.
    - Translate catalog values into search-friendly natural language. Examples:
        - "Easy Piano" → "easy piano arrangement for beginners"
        - "Guitar Tab" → "guitar tablature with standard notation"
        - "Big Note Piano" → "big-note piano edition for early-stage students"
        - "Blues-Jazz-Pop" → "draws on blues, jazz, and pop styles"
        - "Pop-Rock" → "pop-rock song"
    - Pair proper nouns with descriptive anchors so they cluster well in retrieval:
        - "Elvis Presley" alone is a weak anchor; "Elvis Presley's rockabilly classic" is searchable.
        - When artist + tags are both available, use them together in one phrase.
    - The `artist` field names the artist of the ORIGINAL song or recording, NOT a performer on this sheet music arrangement. The customer who buys the score is the performer. Do NOT say the artist "performs", "sings", "plays", or "features" on this edition. Phrase artist references as: "by [artist]", "[artist]'s song", "the [artist] classic", "made famous by [artist]", or similar attribution.
    - Use ONLY these dimensions IF the data provides them. Omit otherwise:
      (1) title, artist, composer (always start here)
      (2) arrangement_category + smd_category, rendered as natural prose (never paste verbatim)
      (3) tags, translated into prose (never paste "X-Y-Z" verbatim)
      (4) voicing (SATB, TTBB, SSA, 2-Part) or instrumentation
      (5) difficulty_level — use the exact phrase from the data (e.g. "Grade 2-3"). Do NOT invent "beginner" or "easy".
      (6) key, time signature, or tempo_marking — only if explicitly provided
      (7) period, genre, or style words
    - Mention the publisher (brand) AT MOST ONCE, briefly, near the end. It is fine to omit entirely. NEVER lead with the publisher.
    - TRANSLATE, DO NOT EXTRAPOLATE. Render catalog values as natural search prose. DO NOT invent any of the following — the data DOES NOT contain these facts:
      duration ("about X minutes"), syncopation level, ornamentation, finger
      independence, position shifts, melodic range, voice leading, technical
      complexity, harmonic complexity, "moving inner voices", "stepwise melodic
      motion", or any technique-specific claim. If you can't tell from the data,
      DO NOT speculate.
    - Use real search terms naturally: instrument names, voicings, genre words,
      era words, use-case words ("for beginners", "for worship", "for school band").
    - DO NOT pad with generic boilerplate. NO "Suitable for sight-reading practice",
      "ideal for technique building", "About 2 minutes long" — unless the data
      explicitly supports the claim.
    - DO NOT echo marketing tails like "Digital Sheet Music" or "Print and Download" from the title.
    - Do NOT produce a bullet list.
    </rules>

    <examples>
    - "Good Rockin' Tonight by Elvis Presley is a guitar tab arrangement of the rockabilly classic, drawing on blues, jazz, and pop influences. Suitable for intermediate guitarists exploring early rock and roll, the edition includes both standard notation and tablature. Published by Hal Leonard."
    - "Boulevard Of Broken Dreams by Green Day is a Grade 1 easy piano arrangement of the punk-pop-rock song, set in G minor common time. Suitable for early-stage pianists working on contemporary repertoire, the simplified setting keeps the well-known melody approachable for beginning students."
    - "Mama, I'm Coming Home (arr. Roger Holmes) by Ozzy Osbourne is a jazz ensemble arrangement of the rock ballad. The quasi-rock ballad feel suits high school and college big bands, with drums, alto sax, tenor sax, baritone sax, trumpet, trombone, and rhythm section."
    - "Rejoice! Christ Is Born! by Joseph M. Martin is an SATB choir piece in cut time, set in G major. The Christmas anthem suits church services and seasonal concerts, marked 'cheerfully' at quarter = 92."
    - "The First Noel arranged by David Chase is an SATB choir setting of the traditional Christmas carol in D major. Marked moderato (quarter ca. 104), dolce. Works well for carol services and seasonal worship programs."
    - "This Old Man (arr. Phillip Keveren) is a Grade 1 easy piano arrangement of the traditional nursery rhyme. The familiar folk melody with straightforward harmonies works for early-stage piano students and first-recital pieces."
    </examples>

    <data>
    %{metadata_json}
    </data>

    <output_format>
    Return valid JSON with this structure: {"description": "your description here"}
    </output_format>
  PROMPT

  # Traditional difficulty labels - used to detect hallucinated difficulty
  # when no difficulty_level was provided
  HALLUCINATION_WORDS = %w[beginner easy].freeze

  # All words/phrases that indicate difficulty was mentioned
  # Includes pedagogical grades and neutral phrases
  DIFFICULTY_INDICATORS = [
    /grade \d/i,                    # "Grade 4", "Grade 4-5"
    /unterstufe/i,                  # German grades
    /mittelstufe/i,
    /oberstufe/i,
    /technically accessible/i,      # Neutral phrases
    /moderate technical demands/i,
    /technically demanding/i,
    /virtuosic/i,
    /virtuoso/i,
    /intermediate/i,
    /advanced/i,
    /expert/i
  ].freeze

  def initialize(client: nil)
    @client = client || LlmClient.new
  end

  def generate(score)
    metadata = build_metadata(score)
    prompt = format(template_for(score), metadata_json: metadata.to_json)

    response = @client.chat_json(prompt)
    description = response["description"].to_s.strip

    # Retry once if LLM hallucinated "beginner"/"easy" when we didn't provide those
    if metadata[:difficulty_level].nil? && hallucinated_difficulty?(description)
      description = regenerate_without_difficulty(score, metadata)
    end

    issues = validate(description, expects_difficulty: metadata[:difficulty_level].present?, min_length: min_length_for(score))

    # Flag if retry still hallucinated difficulty
    if metadata[:difficulty_level].nil? && hallucinated_difficulty?(description)
      issues << "hallucinated_difficulty"
    end
    Result.new(description: description, issues: issues, error: nil)
  rescue JSON::ParserError => e
    Result.new(description: nil, issues: [], error: "JSON parse error: #{e.message}")
  rescue LlmClient::Error => e
    Result.new(description: nil, issues: [], error: e.message)
  rescue StandardError => e
    Result.new(description: nil, issues: [], error: "#{e.class}: #{e.message}")
  end

  private

  def validate(description, expects_difficulty: true, min_length: 200)
    issues = []

    return ["too_short"] if description.blank? || description.length < min_length
    issues << "too_long" if description.length > 1500

    desc_lower = description.downcase
    issues << "missing_difficulty" if expects_difficulty && !mentions_difficulty?(description)
    issues << "jargon" if JARGON_TERMS.any? { |t| desc_lower.include?(t) }
    issues << "bullet_list" if description.count("-") > 3 && description.count(".") < 2

    issues
  end

  # Check if LLM used misleading difficulty words we explicitly avoid
  def hallucinated_difficulty?(text)
    HALLUCINATION_WORDS.any? { |word| text.downcase.include?(word) }
  end

  # Check if difficulty was properly mentioned (grades, neutral phrases, etc.)
  def mentions_difficulty?(text)
    DIFFICULTY_INDICATORS.any? { |pattern| text.match?(pattern) }
  end

  def regenerate_without_difficulty(score, metadata)
    stronger_prompt = format(template_for(score), metadata_json: metadata.to_json)
    stronger_prompt += "\n\nIMPORTANT: difficulty_level was NOT provided. Do NOT mention difficulty at all."

    response = @client.chat_json(stronger_prompt)
    response["description"].to_s.strip
  end

  def template_for(score)
    score.extraction_extracted? ? RICH_PROMPT : SPARSE_PROMPT
  end

  def min_length_for(score)
    score.extraction_extracted? ? 200 : 100
  end

  def build_metadata(score)
    score.extraction_extracted? ? build_rich_metadata(score) : build_sparse_metadata(score)
  end

  def build_common_metadata(score)
    {
      title: score.clean_title.presence || score.title,
      composer: clean_composer(score.composer),
      period: score.period,
      genre: score.genre,
      voicing: score.voicing,
      instruments: score.instruments,
      key_signature: score.key_signature,
      time_signature: map_time_sig(score.time_signature),
      difficulty_level: difficulty_label(score),
      has_vocal: score.has_vocal,
      is_instrumental: score.is_instrumental?,
      tempo_marking: score.tempo_marking
    }
  end

  def build_rich_metadata(score)
    build_common_metadata(score).merge(
      clefs_used: map_clefs(score.clefs_used),
      is_virtuoso: virtuoso?(score),
      duration_minutes: format_duration_minutes(score.effective_duration),
      num_parts: bucket(score.num_parts, [1, 2, 4, 8], %w[solo duo small_ensemble ensemble large_ensemble]),
      ambitus: bucket(score.ambitus_semitones, [12, 24, 36], %w[narrow moderate wide very_wide]),
      chromatic_passages: bucket_01(score.chromatic_ratio),
      syncopated_rhythms: bucket_01(score.syncopation_level),
      contrapuntal_texture: bucket(score.vertical_density, [1.1, 1.4, 1.8], %w[thin moderate rich very_rich]),
      melodic_motion: stepwise_motion(score.stepwise_motion_ratio),
      has_dynamics: score.has_dynamics,
      has_articulations: score.has_articulations,
      has_ornaments: score.has_ornaments,
      sections: extract_sections(score.expression_markings)
    ).compact
  end

  def build_sparse_metadata(score)
    build_common_metadata(score).merge(
      artist: score.artist,
      brand: score.brand,
      arrangement_category: score.arrangement_category,
      smd_category: score.smd_category,
      tags: score.tags
    ).compact
  end

  def clean_composer(composer)
    return nil if composer.blank?
    return nil if COMPOSER_PLACEHOLDERS.any? { |p| composer.casecmp?(p) }
    composer
  end

  # Extract movement/section names from expression_markings.
  # Improves search recall: "sarabande" finds suites containing sarabandes.
  def extract_sections(expr)
    return nil if expr.blank?

    expr_lower = expr.downcase
    found = MOVEMENT_NAMES.select { |name| expr_lower.include?(name) }
    return nil if found.empty?

    found.join(", ")
  end

  # Returns difficulty label for search_text generation.
  #
  # Priority:
  # 1. Pedagogical grade (LLM-verified) - use verbatim with German equivalent
  # 2. Algorithm-only - use NEUTRAL language (never "beginner" or "easy")
  #
  # This prevents misleading search results like Sor Etudes showing up
  # for "easy beginner guitar" searches.
  def difficulty_label(score)
    # Pedagogical grade takes priority - it's pedagogically accurate
    if score.pedagogical_grade.present?
      label = score.pedagogical_grade
      label += " (#{score.pedagogical_grade_de})" if score.pedagogical_grade_de.present?
      return label
    end

    # Algorithm-only: use neutral language to avoid misleading embeddings
    # "technically accessible" won't match "easy beginner" searches
    level = score.computed_difficulty
    return nil unless level

    case level
    when 1, 2 then "technically accessible"   # NOT "beginner" or "easy"
    when 3    then "moderate technical demands"
    when 4    then "technically demanding"
    when 5    then "virtuosic"
    end
  end

  # Virtuoso = showpiece requiring exceptional technique
  # Uses same point-based instrument-aware algorithm as scores.rake
  # Returns true if piece would trigger the virtuoso bonus
  def virtuoso?(score)
    # Must be at least advanced difficulty to be virtuoso
    return false unless score.computed_difficulty && score.computed_difficulty >= 4

    instrument = detect_instrument_family(score)
    chromatic = score.chromatic_ratio.to_f
    largest = score.largest_interval.to_i
    polyphony = score.vertical_density.to_f
    leaps = score.leaps_per_measure.to_f

    # Same virtuoso bonus conditions from scores.rake
    case instrument
    when :guitar
      # Guitar virtuoso: high polyphony + chromatic
      polyphony > 1.8 && chromatic >= 0.6
    when :violin, :cello, :strings
      # String virtuoso: many leaps + large intervals
      leaps > 3 && largest >= 20
    when :vocal
      # Vocal virtuoso: chromatic + large intervals
      chromatic >= 0.6 && largest >= 12
    when :keyboard
      # Piano virtuoso: high chromatic + complex polyphony
      chromatic >= 0.8 && polyphony > 1.5
    else
      # Default virtuoso: chromatic + intervals
      chromatic >= 0.8 && largest >= 24
    end
  end

  def detect_instrument_family(score)
    instruments = score.instruments.to_s.downcase

    return :guitar if instruments.include?("guitar")
    return :violin if instruments.include?("violin")
    return :cello if instruments.include?("cello")
    return :strings if instruments.match?(/viola|double bass|string quartet|strings/)
    return :keyboard if instruments.match?(/piano|organ|harpsichord|keyboard|clavichord/)
    return :vocal if score.has_vocal?
    return :vocal if instruments.match?(/voice|choir|chorus|satb|soprano|alto|tenor|bass|choral/)

    :other
  end

  def format_duration_minutes(seconds)
    return nil if seconds.blank? || seconds <= 0
    minutes = (seconds / 60.0).round
    return "about 1 minute" if minutes <= 1
    "about #{minutes} minutes"
  end

  def bucket(value, cuts, labels)
    return nil if value.nil?
    cuts.each_with_index { |cut, i| return labels[i] if value <= cut }
    labels.last
  end

  def bucket_01(value)
    return nil if value.nil?
    case value
    when 0...0.33 then "low"
    when 0.33...0.66 then "medium"
    else "high"
    end
  end

  def stepwise_motion(ratio)
    return nil if ratio.nil?
    case ratio
    when 0.6.. then "stepwise"
    when 0.4.. then "mixed"
    else "leapy"
    end
  end

  def map_time_sig(ts)
    return nil if ts.blank?
    {
      "4/4" => "four-four (common time)",
      "3/4" => "three-four (waltz time)",
      "2/4" => "two-four",
      "6/8" => "six-eight",
      "2/2" => "cut time"
    }[ts] || ts
  end

  def map_clefs(clefs)
    return nil if clefs.blank?
    names = { "f" => "bass", "g" => "treble", "c" => "alto" }
    clefs.split(",").map { |c| names[c.strip.downcase] || c.strip }.join(" and ")
  end
end
