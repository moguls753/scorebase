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
  DIFFICULTY_TERMS = %w[
    easy beginner simple
    intermediate moderate
    advanced challenging
    virtuoso demanding expert
  ].freeze

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

  Result = Data.define(:description, :issues, :error) do
    def success? = error.nil? && issues.empty?
  end

  PROMPT = <<~PROMPT
    <role>
    You write rich, searchable descriptions for a sheet music catalog used by music teachers, choir directors, church musicians, and university professors. Follow the <rules/> and the <steps/> to generate an answer. You can find some positive examples in the <examples/> section.
    </role>

    <rules>
    - Write 5–7 sentences (150-250 words) in a paragraph that gives a complete picture of the piece.
    - START with the title. If composer is provided, include it (e.g., "Étude Op.6 by Fernando Sor is..."). If no composer, start with just the title (e.g., "O Come All Ye Faithful is a beloved Christmas hymn...").
    - Include ALL of these elements:
      (1) TITLE (and COMPOSER if provided) in the first sentence
      (2) DIFFICULTY: Use the difficulty_level field. Only use "virtuoso" if is_virtuoso is true; otherwise use easy/beginner, intermediate, or advanced.
      (3) CHARACTER (2-3 mood/style words: gentle, dramatic, contemplative, energetic, majestic, lyrical, playful, solemn, etc.)
      (4) BEST FOR (specific uses: sight-reading practice, student recitals, church services, exam repertoire, technique building, competitions, teaching specific skills)
      (5) MUSICAL FEATURES (texture, harmonic language, notable patterns like arpeggios, scales, counterpoint)
      (6) KEY DETAILS (duration, instrumentation, key, period/style)
    - Use words musicians actually search: "sight-reading", "recital piece", "exam repertoire", "church anthem", "teaching piece", "competition", "Baroque counterpoint", "lyrical melody", "chromatic passages", "syncopated rhythms".
    - NEVER use academic metric-compounds like "chromatic complexity", "vertical density", "melodic complexity", "rhythmic variety". The data uses searchable terms already - use them naturally in prose.
    - STRICT: Only mention instruments, voicing, genre, and other details that appear in <data/>. Do not invent or assume facts not present in the data.
    - Do not produce a bullet point list.
    </rules>

    <steps>
    1) Read the metadata: identify instrument, genre, key, time signature, texture, range, duration.
    2) Choose exactly one DIFFICULTY from difficulty_level. Only say "virtuoso" if is_virtuoso is true.
    3) Pick 2–3 CHARACTER words based on metadata cues (key, tempo, texture suggest mood).
    4) List 2–3 specific BEST FOR uses (teaching, performance, liturgical, exam, etc.).
    5) Note interesting MUSICAL FEATURES worth mentioning (counterpoint, ornamentation, range demands).
    6) Write 5–7 flowing sentences covering all elements above.
    </steps>

    <examples>
    - "Sonatina in C major by Muzio Clementi is an easy piano piece with a gentle, flowing character. The simple melodic lines and steady rhythms make it ideal for first-year students developing hand coordination. Perfect for sight-reading practice or as an early recital piece. The piece stays in a comfortable range and uses basic chord patterns. About 2 minutes long, it works well for building confidence in young pianists."
    - "Ascendit Deus by Peter Philips is an advanced SATB anthem with a joyful, majestic character, well-suited for Easter services or festive choir concerts. The four-part writing features independent voice lines and some chromatic passages that require confident singers. Soprano part reaches B5, so ensure your section can handle the tessitura. The energetic rhythms and triumphant harmonies make this a rewarding showpiece. About 4 minutes long."
    - "Violin Sonata No. 1 by Johannes Brahms is an intermediate violin sonata in the Romantic style, lyrical and deeply expressive. Features singing melodic lines with moderate technical demands including some position work and dynamic contrasts. Excellent choice for student recitals, conservatory auditions, or as exam repertoire. The piano accompaniment provides rich harmonic support. A substantial work around 25 minutes that develops musicality and interpretation skills."
    - "O Come All Ye Faithful is a beloved intermediate Christmas hymn for SATB choir with organ accompaniment. The stately, joyful character makes it a staple of holiday church services and carol concerts. Features straightforward four-part harmony with some moving inner voices. The familiar melody is accessible for congregational singing while offering enough interest for trained choirs. About 3 minutes long, ideal for processionals or as a service closer."
    </examples>

    <data>
    %{metadata_json}
    </data>

    <output_format>
    Return valid JSON with this structure: {"description": "your description here"}
    </output_format>
  PROMPT

  def initialize(client: nil)
    @client = client || LlmClient.new
  end

  def generate(score)
    metadata = build_metadata(score)
    prompt = format(PROMPT, metadata_json: metadata.to_json)

    response = @client.chat_json(prompt)
    description = response["description"].to_s.strip

    issues = validate(description)
    Result.new(description: description, issues: issues, error: nil)
  rescue JSON::ParserError => e
    Result.new(description: nil, issues: [], error: "JSON parse error: #{e.message}")
  rescue LlmClient::Error => e
    Result.new(description: nil, issues: [], error: e.message)
  rescue StandardError => e
    Result.new(description: nil, issues: [], error: "#{e.class}: #{e.message}")
  end

  private

  def validate(description)
    issues = []

    return ["too_short"] if description.blank? || description.length < 200
    issues << "too_long" if description.length > 1500

    desc_lower = description.downcase
    issues << "missing_difficulty" unless DIFFICULTY_TERMS.any? { |t| desc_lower.include?(t) }
    issues << "jargon" if JARGON_TERMS.any? { |t| desc_lower.include?(t) }
    issues << "bullet_list" if description.count("-") > 3 && description.count(".") < 2

    issues
  end

  def build_metadata(score)
    # Omit placeholder composers - score still has valuable metadata
    composer = score.composer
    composer = nil if composer.present? && COMPOSER_PLACEHOLDERS.any? { |p| composer.casecmp?(p) }

    {
      title: score.title,
      composer: composer,
      period: score.period,
      genre: score.genre,
      voicing: score.voicing,
      instruments: score.instruments,
      key_signature: score.key_signature,
      time_signature: map_time_sig(score.time_signature),
      clefs_used: map_clefs(score.clefs_used),
      difficulty_level: difficulty_label(score),
      is_virtuoso: virtuoso?(score),
      duration_minutes: format_duration_minutes(score.duration_seconds),
      num_parts: bucket(score.num_parts, [1, 2, 4, 8], %w[solo duo small_ensemble ensemble large_ensemble]),
      ambitus: bucket(score.ambitus_semitones, [12, 24, 36], %w[narrow moderate wide very_wide]),
      chromatic_passages: bucket_01(score.chromatic_complexity),
      syncopated_rhythms: bucket_01(score.syncopation_level),
      contrapuntal_texture: bucket(score.vertical_density, [1.1, 1.4, 1.8], %w[thin moderate rich very_rich]),
      melodic_motion: stepwise_motion(score.stepwise_motion_ratio),
      has_dynamics: score.has_dynamics,
      has_articulations: score.has_articulations,
      has_ornaments: score.has_ornaments,
      has_vocal: score.has_vocal,
      is_instrumental: score.is_instrumental?
    }.compact
  end

  # Use computed_difficulty (1-5) from music21 extraction
  def difficulty_label(score)
    level = score.computed_difficulty || 3
    case level
    when 1 then "beginner"
    when 2 then "easy"
    when 3 then "intermediate"
    when 4 then "advanced"
    when 5 then "expert"
    else "intermediate"
    end
  end

  # Virtuoso = showpiece requiring exceptional technique
  # Uses same point-based instrument-aware algorithm as scores.rake
  # Returns true if piece would trigger the virtuoso bonus
  def virtuoso?(score)
    # Must be at least advanced difficulty to be virtuoso
    return false unless score.computed_difficulty && score.computed_difficulty >= 4

    instrument = detect_instrument_family(score)
    chromatic = score.chromatic_complexity.to_f
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

    # Prioritize specific instruments over has_vocal
    return :guitar if instruments.match?(/\bguitar\b/i)
    return :violin if instruments.match?(/\bviolin\b/i)
    return :cello if instruments.match?(/\bcello\b/i)
    return :strings if instruments.match?(/\b(viola|double bass|string quartet|strings)\b/i)
    return :keyboard if instruments.match?(/\b(piano|organ|harpsichord|keyboard|clavichord)\b/i)

    return :vocal if score.has_vocal
    return :vocal if instruments.match?(/\b(voice|choir|chorus|satb|soprano|alto|tenor|bass|choral)\b/i)

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
