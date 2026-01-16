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

  # Banned boilerplate phrases that destroy embedding distinctiveness
  # NOTE: Recommendation phrases (suitable for, ideal for, etc.) removed - they're useful for search
  BANNED_PHRASES = [
    "with a gentle",
    "with a contemplative",
    "with a lyrical",
    "with a serene",
    "with a tender"
  ].freeze

  # Banned sentence starters that create identical embeddings
  BANNED_STARTERS = [
    /\A[A-Z][^,]+ by [A-Z][^,]+ is an?\s/i,  # "X by Y is a/an..."
    /\AThis (piece|work|composition|song|hymn|anthem) /i,
    /\AThe piece /i
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

  PROMPT = <<~PROMPT
    <role>
    You write searchable descriptions for a sheet music database. Your text will be converted to embeddings for semantic search. The goal is FINDABILITY: users must find THIS specific piece when they search for its distinctive features.
    </role>

    <critical_embedding_rules>
    These rules exist because embedding models weight all text equally. Boilerplate phrases dilute the signal from distinctive terms.

    BANNED PHRASES (these appear in every description and destroy search precision):
    - "with a [adjective], [adjective] character"
    - "suitable for" / "well-suited for" / "making it suitable"
    - "ideal for" / "excellent for" / "perfect for"
    - "About X minutes long"
    - "making it an excellent choice"
    - "this piece is" / "the piece features"
    - "for developing [instrument]ists"

    BANNED SENTENCE STARTERS (creates identical embeddings):
    - "[Title] by [Composer] is a/an..."
    - "This [genre] features..."
    - "The piece..."

    REQUIRED: Every description must be structurally unique. Vary your sentence patterns.
    </critical_embedding_rules>

    <what_makes_pieces_findable>
    Users search for SPECIFIC combinations. Front-load these distinctive identifiers:

    1. INSTRUMENTATION (most important for search):
       - "Solo piano" / "Piano solo" / "Klavier"
       - "SATB choir with organ" / "Mixed chorus a cappella"
       - "Flute and guitar duo" / "Violin and piano"
       - "Orchestra with trumpet, oboe, strings"
       - List ALL instruments from the data prominently

    2. FORM & STRUCTURE:
       - Suite movements: "allemande, courante, sarabande, gigue"
       - "Prelude and fugue" / "Theme and variations"
       - "Sonata form" / "Rondo" / "ABA form"

    3. KEY & MODE (people search by key!):
       - "G-sharp minor" / "B-flat major" / "D minor"
       - "Modal" / "Chromatic" / "Diatonic"

    4. DIFFICULTY (CRITICAL - MUST include if provided):
       - "Grade 1-2 (Unterstufe)" / "Grade 4-5 (Mittelstufe I)"
       - ALWAYS include the exact grade from difficulty_level in data
       - This is the #1 search criterion for teachers - NEVER omit if provided
       - If difficulty_level is NOT in the data, omit entirely

    5. GENRE & PERIOD:
       - "Baroque fugue" / "Renaissance madrigal" / "Romantic lied"
       - "Jazz standard" / "Folk song arrangement" / "Christmas carol"

    6. COMPOSER (for famous ones, include nationality/era):
       - "Bach" alone is fine, but "J.S. Bach, Baroque" helps
       - "Mozart, Classical era" / "Ellington, jazz"

    7. PURPOSE & OCCASION:
       - "church service" / "wedding" / "funeral"
       - "exam repertoire" / "competition piece" / "sight-reading"
       - "Christmas" / "Easter" / "Advent"
    </what_makes_pieces_findable>

    <structure_templates>
    Rotate between these structures. NEVER use the same pattern twice in a row:

    A) INSTRUMENTATION-FIRST:
       "For [instruments], [Composer]'s [Title] in [key]..."

    B) GENRE-FIRST:
       "[Genre] from the [period]: [Title] by [Composer]..."

    C) DIFFICULTY-FIRST (if grade provided):
       "Grade [X] [instrument] piece: [Title]..."

    D) PURPOSE-FIRST:
       "[Occasion/purpose] music: [Title] for [instruments]..."

    E) FORM-FIRST (for suites, sonatas):
       "[Form] in [key] comprising [movements]: [Composer]'s [Title]..."

    F) QUESTION-STYLE:
       "Looking for [specific feature]? [Title] offers..."
    </structure_templates>

    <character_vocabulary>
    Choose 1-2 words that PRECISELY fit the metadata. Be specific, not generic:

    ENERGY: driving, urgent, restless, serene, tranquil, meditative, stormy, explosive
    MOOD: wistful, triumphant, anguished, tender, jubilant, haunting, bittersweet, noble
    STYLE: dance-like, hymn-like, operatic, pastoral, martial, processional, improvisatory
    TEXTURE: polyphonic, homophonic, antiphonal, imitative, chordal, contrapuntal

    AVOID overusing: gentle, contemplative, lyrical (these are in 80%% of current descriptions)
    </character_vocabulary>

    <data_rules>
    - CRITICAL: If difficulty_level is provided, you MUST include it verbatim. Teachers search by grade!
    - Include ALL instruments listed in the data - this is critical for search
    - Include the EXACT key signature (G-sharp minor, not just "minor key")
    - If "sections" lists movements (allemande, courante, etc.), list them ALL
    - Include tempo marking if provided
    - STRICT: Only mention what appears in <data/>. Never invent.
    - If difficulty_level is missing, do NOT mention difficulty at all
    </data_rules>

    <examples>
    GOOD (distinctive, searchable, varied structure):

    "Solo piano, Grade 5-7 (Mittelstufe I/II): Bach's French Suite No. 4 in E-flat major BWV 815. A Baroque dance suite comprising allemande, courante, sarabande, gavotte, menuet, air, and gigue. E-flat major, elegant and stately. Develops independence between hands through polyphonic texture. 15 minutes. Exam repertoire, recital centerpiece."

    "For SATB chorus with trumpet, oboe, and orchestra: Bach's Mass in B minor BWV 232. Monumental sacred work, Grade 6-8 (Oberstufe). Latin mass setting featuring complex fugal choruses and expressive arias. Demands confident choral forces and Baroque orchestral forces including natural trumpet. Concert mass, not liturgical use. 110 minutes."

    "Flute and classical guitar duo, Grade 3-4 (Mittelstufe I): Giuliani's 16 Pièces faciles et agréables Op. 74. Charming Classical-era chamber music. Stepwise melodies, light texture. Student recitals, chamber music introduction. 20 minutes total."

    "Renaissance madrigal for SATB a cappella: Morley's 'April is in my mistress' face.' English madrigal, imitative polyphony, word-painting on 'April' and 'spring.' Grade 5-6. Chamber choir, madrigal dinner, Renaissance program."

    "Jazz big band: Ellington's Caravan. Trumpet, alto sax, tenor sax, trombone, guitar, piano, bass, drums. Exotic, driving, syncopated. F major. Grade 5-6. Jazz ensemble concert, swing dance."

    BAD (generic, templated, unfindable):

    "Caravan by Duke Ellington is a jazz piece with a lively, energetic character. The piece features syncopated rhythms and a rich texture, making it suitable for jazz ensembles. About 4 minutes long, ideal for concerts." ← BANNED PHRASES, NO INSTRUMENTS LISTED, GENERIC

    "French Suite No. 4 by Bach is an intermediate piano suite with an elegant, stately character. Excellent for students working on Baroque style. Features dance movements and contrapuntal texture. About 15 minutes long." ← NO KEY, NO MOVEMENT NAMES, TEMPLATE START
    </examples>

    <data>
    %{metadata_json}
    </data>

    <output_format>
    Return valid JSON: {"description": "your 100-180 word description"}
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
    prompt = format(PROMPT, metadata_json: metadata.to_json)

    response = @client.chat_json(prompt)
    description = response["description"].to_s.strip

    issues = validate(description, expects_difficulty: metadata[:difficulty_level].present?)

    # Flag issues - no auto-retry, let it fail so we can rerun manually
    if metadata[:difficulty_level].nil? && hallucinated_difficulty?(description)
      issues << "hallucinated_difficulty"
    end

    if (banned = find_banned_phrase(description))
      issues << "banned_phrase:#{banned}"
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

  def validate(description, expects_difficulty: true)
    issues = []

    return ["too_short"] if description.blank? || description.length < 150
    issues << "too_long" if description.length > 1200

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

  # Find which banned phrase was used (returns phrase or nil)
  def find_banned_phrase(text)
    desc_lower = text.downcase

    # Check phrase list
    found_phrase = BANNED_PHRASES.find { |phrase| desc_lower.include?(phrase) }
    return found_phrase if found_phrase

    # Check starter patterns
    BANNED_STARTERS.each_with_index do |pattern, i|
      return "STARTER_#{i}" if text.match?(pattern)
    end

    nil
  end

  # Check if difficulty was properly mentioned (grades, neutral phrases, etc.)
  def mentions_difficulty?(text)
    DIFFICULTY_INDICATORS.any? { |pattern| text.match?(pattern) }
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
      has_vocal: score.has_vocal,
      is_instrumental: score.is_instrumental?,
      sections: extract_sections(score.expression_markings),
      tempo_marking: score.tempo_marking
    }.compact
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
