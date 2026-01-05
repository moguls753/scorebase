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

  JARGON_TERMS = [
    "chromatic complexity",
    "polyphonic density",
    "pitch palette"
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
    - Include ALL of these elements:
      (1) DIFFICULTY (exactly one: easy/beginner, intermediate, advanced, virtuoso)
      (2) CHARACTER (2-3 mood/style words: gentle, dramatic, contemplative, energetic, majestic, lyrical, playful, solemn, etc.)
      (3) BEST FOR (specific uses: sight-reading practice, student recitals, church services, exam repertoire, technique building, competitions, teaching specific skills)
      (4) MUSICAL FEATURES (texture, harmonic language, notable patterns like arpeggios, scales, counterpoint)
      (5) KEY DETAILS (duration, instrumentation, key, period/style)
    - Use words musicians actually search: "sight-reading", "recital piece", "exam repertoire", "church anthem", "teaching piece", "competition", "Baroque counterpoint", "lyrical melody".
    - Write natural prose. Translate technical metadata into musical descriptions (e.g., "high chromaticism" → "rich harmonic language with expressive accidentals").
    - Only use what is in the <data/> section. Do not invent facts.
    - Do not produce a bullet point list.
    </rules>

    <steps>
    1) Read the metadata: identify instrument, genre, key, time signature, texture, range, duration.
    2) Choose exactly one DIFFICULTY from: easy/beginner, intermediate, advanced, virtuoso (from difficulty_level field).
    3) Pick 2–3 CHARACTER words based on metadata cues (key, tempo, texture suggest mood).
    4) List 2–3 specific BEST FOR uses (teaching, performance, liturgical, exam, etc.).
    5) Note interesting MUSICAL FEATURES worth mentioning (counterpoint, ornamentation, range demands).
    6) Write 5–7 flowing sentences covering all elements above.
    </steps>

    <examples>
    - "Easy beginner piano piece in C major with a gentle, flowing character. The simple melodic lines and steady rhythms make it ideal for first-year students developing hand coordination. Perfect for sight-reading practice or as an early recital piece. The piece stays in a comfortable range and uses basic chord patterns. About 2 minutes long, it works well for building confidence in young pianists."
    - "Advanced SATB anthem with a joyful, majestic character, well-suited for Easter services or festive choir concerts. The four-part writing features independent voice lines and some chromatic passages that require confident singers. Soprano part reaches B5, so ensure your section can handle the tessitura. The energetic rhythms and triumphant harmonies make this a rewarding showpiece. Approximately 4 minutes."
    - "Intermediate violin sonata in the Romantic style, lyrical and deeply expressive. Features singing melodic lines with moderate technical demands including some position work and dynamic contrasts. Excellent choice for student recitals, conservatory auditions, or as exam repertoire. The piano accompaniment provides rich harmonic support. A substantial work that develops musicality and interpretation skills."
    </examples>

    <data>
    %{metadata_json}
    </data>

    <output_format>
    {"description": "..."}
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
    {
      title: score.title,
      composer: score.composer,
      period: score.period,
      genre: score.genre,
      voicing: score.voicing,
      instruments: score.instruments,
      key_signature: score.key_signature,
      time_signature: map_time_sig(score.time_signature),
      clefs_used: map_clefs(score.clefs_used),
      difficulty_level: difficulty_words(score.melodic_complexity),
      num_parts: bucket(score.num_parts, [1, 2, 4, 8], %w[solo duo small_ensemble ensemble large_ensemble]),
      page_count: bucket(score.page_count, [1, 3, 7, 15], %w[very_short short medium long very_long]),
      ambitus: bucket(score.ambitus_semitones, [12, 24, 36], %w[narrow moderate wide very_wide]),
      length_in_measures: bucket(score.measure_count, [32, 80, 160], %w[short medium long very_long]),
      chromaticism: bucket_01(score.chromatic_complexity),
      syncopation: bucket_01(score.syncopation_level),
      rhythmic_variety: bucket_01(score.rhythmic_variety),
      melodic_complexity: bucket_01(score.melodic_complexity),
      polyphonic_density: bucket(score.polyphonic_density, [1.1, 1.4, 1.8], %w[low medium high very_high]),
      melodic_motion: stepwise_motion(score.stepwise_motion_ratio),
      has_dynamics: score.has_dynamics,
      has_articulations: score.has_articulations,
      has_ornaments: score.has_ornaments,
      has_vocal: score.has_vocal,
      is_instrumental: score.is_instrumental
    }.compact
  end

  def difficulty_words(melodic_complexity)
    return %w[intermediate moderate] if melodic_complexity.nil?
    case melodic_complexity
    when 0...0.3 then %w[easy beginner simple]
    when 0.3...0.5 then %w[intermediate moderate]
    when 0.5...0.7 then %w[advanced challenging]
    else %w[virtuoso demanding expert]
    end
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
