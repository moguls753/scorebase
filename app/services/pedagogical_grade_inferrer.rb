# frozen_string_literal: true

# Infers pedagogical grade for known pieces using LLM.
# Returns standard teaching grades (ABRSM/RCM international + German Musikschule).
#
# Usage:
#   inferrer = PedagogicalGradeInferrer.new(client: client)
#   results = inferrer.infer(scores)
#   results.first.grade         # => "Grade 4-5" or nil
#   results.first.grade_de      # => "Mittelstufe I" or nil
#   results.first.confidence    # => "high", "medium", "low"
#   results.first.success?      # => true (API call succeeded)
#   results.first.found?        # => true (grade was identified)
#
class PedagogicalGradeInferrer
  Result = Data.define(:grade, :grade_de, :confidence, :reasoning, :error) do
    def success? = error.nil?
    def found? = grade.present?
  end

  # Valid international grade patterns for validation
  # German grades are not validated - LLM output varies (e.g., "Mittelstufe I" vs "Mittelstufe")
  VALID_GRADES = [
    /^Grade [1-8]$/,
    /^Grade [1-8]-[1-8]$/,
    /^Diploma\+?$/
  ].freeze

  PROMPT = <<~PROMPT
    You are a music pedagogy expert. Determine the standard teaching grade for this piece.

    <piece>
    Title: %{title}
    Composer: %{composer}
    Instrument: %{instruments}
    </piece>

    <task>
    1. If this is a well-known piece with an established pedagogical grade, return that grade.
    2. If unknown or obscure, return null for both grades.
    3. Do NOT guess - only return grades for pieces you're confident about.
    </task>

    <grade_systems>
    International (ABRSM/RCM style):
    - Grade 1: True beginner (0.5-1 years)
    - Grade 2: Elementary (1-1.5 years)
    - Grade 3: Late elementary (1.5-2.5 years)
    - Grade 4: Early intermediate (2.5-4 years)
    - Grade 5: Intermediate (4-5 years)
    - Grade 6: Late intermediate (5-7 years)
    - Grade 7: Early advanced (7-9 years)
    - Grade 8: Advanced (9-11 years)
    - Diploma+: Professional level (11+ years)

    German (Musikschule):
    - Unterstufe I = Grade 1-2 (Anfänger)
    - Unterstufe II = Grade 2-3 (Fortgeschrittene Anfänger)
    - Mittelstufe I = Grade 4-5 (Mittelstufe)
    - Mittelstufe II = Grade 5-6 (Gehobene Mittelstufe)
    - Oberstufe = Grade 7-8 (Fortgeschritten)
    - Künstlerische Ausbildung = Diploma+ (Professionell)
    </grade_systems>

    <examples>
    - Sor Op.6 Etudes (guitar) -> Grade 4-5, Mittelstufe I
    - Bach 2-Part Inventions (piano) -> Grade 5-6, Mittelstufe II
    - Für Elise (piano) -> Grade 4, Mittelstufe I
    - Czerny Op.599 (piano) -> Grade 1-3, Unterstufe I - Unterstufe II
    - Burgmüller Op.100 (piano) -> Grade 2-3, Unterstufe II
    - Carcassi Op.60 No.1-7 (guitar) -> Grade 2-4, Unterstufe II - Mittelstufe I
    - Recuerdos de la Alhambra (guitar) -> Grade 8, Oberstufe
    - Bach Cello Suites (cello) -> Grade 7-8, Oberstufe
    - Chopin Ballades (piano) -> Grade 8, Oberstufe
    - Unknown piece by unknown composer -> null
    </examples>

    <output>
    Return JSON only:
    {
      "grade_international": "Grade X" or "Grade X-Y" or null,
      "grade_german": "German level name" or null,
      "confidence": "high" or "medium" or "low",
      "reasoning": "Brief explanation (1 sentence)"
    }
    </output>
  PROMPT

  BATCH_PROMPT = <<~PROMPT
    You are a music pedagogy expert. Determine the standard teaching grade for each piece.

    %{scores_data}

    <task>
    For each piece:
    1. If well-known with established pedagogical grade, return that grade.
    2. If unknown/obscure, return null for both grades.
    3. Do NOT guess - only return grades for pieces you're confident about.
    </task>

    <grade_systems>
    International: Grade 1-8 (beginner to advanced), Diploma+ (professional)
    German: Unterstufe I/II, Mittelstufe I/II, Oberstufe, Künstlerische Ausbildung
    </grade_systems>

    <output>
    Return JSON:
    {
      "results": [
        {"id": 1, "grade_international": "Grade X-Y" or null, "grade_german": "German level" or null, "confidence": "high|medium|low", "reasoning": "brief"},
        ...
      ]
    }
    </output>
  PROMPT

  def initialize(client: nil)
    @client = client || LlmClient.new
  end

  def infer(scores)
    scores = Array(scores)
    return [] if scores.empty?
    return [infer_single(scores.first)] if scores.one?

    infer_batch(scores)
  end

  private

  def infer_single(score)
    response = @client.chat_json(build_single_prompt(score))
    build_result(response)
  rescue => e
    error_result(e)
  end

  def infer_batch(scores)
    response = @client.chat_json(build_batch_prompt(scores))
    parse_batch_response(response, scores.length)
  rescue => e
    Array.new(scores.length) { error_result(e) }
  end

  def build_single_prompt(score)
    format(PROMPT,
      title: score.title.to_s,
      composer: score.composer.presence || "Unknown",
      instruments: score.instruments.presence || "Unknown"
    )
  end

  def build_batch_prompt(scores)
    scores_data = scores.each_with_index.map { |score, i|
      "#{i + 1}. Title: #{score.title} | Composer: #{score.composer.presence || 'Unknown'} | Instrument: #{score.instruments.presence || 'Unknown'}"
    }.join("\n")

    format(BATCH_PROMPT, scores_data: scores_data)
  end

  def build_result(response)
    return Result.new(grade: nil, grade_de: nil, confidence: nil, reasoning: nil, error: "Invalid response") unless response.is_a?(Hash)

    grade = response["grade_international"]
    grade_de = response["grade_german"]

    # Validate grade format
    if grade.present? && !valid_grade?(grade)
      Rails.logger.warn "[PedagogicalGradeInferrer] Invalid grade format: #{grade}"
      grade = nil
    end

    Result.new(
      grade: grade,
      grade_de: grade_de,
      confidence: response["confidence"],
      reasoning: response["reasoning"],
      error: nil
    )
  end

  def parse_batch_response(response, count)
    results = response["results"] || []

    Array.new(count) do |i|
      result = results.find { |r| r["id"] == i + 1 } || results[i] || {}
      build_result(result)
    end
  end

  def valid_grade?(grade)
    VALID_GRADES.any? { |pattern| grade.match?(pattern) }
  end

  def error_result(error)
    message = case error
    when JSON::ParserError then "JSON parse error"
    when LlmClient::Error then error.message
    when Timeout::Error, Net::OpenTimeout, Net::ReadTimeout then "Network timeout"
    else "#{error.class}: #{error.message}"
    end

    Result.new(grade: nil, grade_de: nil, confidence: nil, reasoning: nil, error: message)
  end
end
