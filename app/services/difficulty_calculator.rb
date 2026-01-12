# frozen_string_literal: true

# Computes instrument-aware difficulty on 1-5 scale.
#
# Only calculates for TRUE SOLO scores:
# - Solo instrument (has_vocal=false, single instrument)
# - Unaccompanied voice (has_vocal=true, no instruments)
#
# Returns nil for:
# - Voice + accompaniment (Solo S, Piano) - use range queries instead
# - Chamber music (Violin, Piano) - ambiguous whose difficulty
# - Ensembles (SATB, String quartet) - multiple independent parts
#
# Uses pure omission: only count metrics that exist.
# Missing tempo? Skip throughput, don't penalize.
#
# Usage:
#   calc = DifficultyCalculator.new(score)
#   calc.applicable? # => true/false
#   calc.difficulty  # => 1..5 or nil if not applicable
#   calc.label       # => "intermediate" or nil
#   calc.breakdown   # => { speed: { source: :throughput, ... }, ... }
#
class DifficultyCalculator
  LABELS = { 1 => "beginner", 2 => "easy", 3 => "intermediate", 4 => "advanced", 5 => "expert" }.freeze

  # Instrument-specific metric weights
  WEIGHTS = {
    keyboard: { speed: 2.5, chord_span: 2.5, interval: 1.0, chromatic: 0.5 },
    guitar:   { speed: 3.0, range: 2.0, chromatic: 1.0 },
    strings:  { speed: 1.5, interval: 2.5, chromatic: 2.5 },
    wind:     { speed: 2.0, interval: 1.5, chromatic: 2.0, range: 1.5 },
    voice:    { speed: 1.0, interval: 2.0, chromatic: 3.0, range: 2.0, leap: 2.5 },
    harp:     { speed: 2.0, chord_span: 2.0, interval: 1.5, chromatic: 1.5 },
    generic:  { speed: 1.5, interval: 1.5, chromatic: 1.5, leap: 1.5 }
  }.freeze

  # Minimum note density to use as speed fallback (when tempo missing)
  DENSITY_THRESHOLD = {
    keyboard: 8, guitar: 6, strings: 8, wind: 7, voice: 10, harp: 8, generic: 8
  }.freeze

  def initialize(score)
    @score = score
    @metrics = ScoreMetricsCalculator.new(score)
    @instrument = detect_instrument
  end

  attr_reader :instrument

  # Check if difficulty calculation is meaningful for this score.
  # Only true solo scores have unambiguous difficulty:
  # - Solo instrument: one performer, clear difficulty target
  # - Unaccompanied voice: singer without accompaniment
  def applicable?
    return @applicable if defined?(@applicable)

    @applicable = if @score.has_vocal?
      # Unaccompanied voice: has_vocal but no instruments
      @score.instruments.blank?
    else
      # Solo instrument: no comma means single instrument
      @score.instruments.present? && !@score.instruments.include?(",")
    end
  end

  def difficulty
    return nil unless applicable?
    @difficulty ||= compute_difficulty
  end

  # Backward compat alias
  alias compute difficulty

  def label
    return nil unless applicable?
    LABELS[difficulty]
  end

  def breakdown
    difficulty # ensure computed
    @breakdown
  end

  private

  def compute_difficulty
    @breakdown = {}
    achieved = 0.0
    max_possible = 0.0

    weights = WEIGHTS[@instrument]

    weights.each do |metric, weight|
      result = send("score_#{metric}")
      next unless result

      achieved += result[:score] * weight
      max_possible += weight
      @breakdown[metric] = result
    end

    @breakdown[:summary] = { achieved: achieved.round(2), max: max_possible.round(2) }
    ratio_to_difficulty(achieved, max_possible)
  end

  def detect_instrument
    name = @score.instruments.to_s.downcase

    return :keyboard if name.match?(/piano|organ|harpsichord|keyboard|clavichord/)
    return :strings  if name.match?(/violin|viola|cello|fiddle|double bass|string quartet|strings/)
    return :guitar   if name.match?(/guitar|lute|vihuela|ukulele/)
    return :wind     if name.match?(/flute|oboe|clarinet|bassoon|saxophone|trumpet|horn|trombone|tuba|recorder/)
    return :harp     if name.match?(/harp/)
    return :voice    if @score.has_vocal? || name.match?(/voice|vocal|solo s|satb|choir|soprano|alto|tenor|(?<![a-z])bass(?!oon)/)

    :generic
  end

  # Metric scoring methods - return { score:, value:, ... } or nil to omit

  def score_speed
    throughput = @metrics.throughput
    density = @metrics.note_density
    threshold = DENSITY_THRESHOLD[@instrument]

    if throughput
      score = score_value(throughput, [[8, 1.0], [5, 0.7], [2.9, 0.4]])
      { source: :throughput, value: throughput.round(1), score: score }
    elsif density && density >= threshold
      score = score_value(density, [[20, 0.7], [15, 0.6], [12, 0.5], [10, 0.4], [8, 0.3], [6, 0.2]])
      { source: :density, value: density.round(1), score: score }
    end
  end

  def score_chord_span
    span = @score.max_chord_span
    return nil unless span

    thresholds = case @instrument
                 when :keyboard then [[16, 1.0], [14, 0.7], [12, 0.3]]
                 else [[14, 1.0], [12, 0.5]]
                 end

    { value: span, score: score_value(span, thresholds) }
  end

  def score_interval
    interval = @score.largest_interval
    return nil unless interval

    thresholds = case @instrument
                 when :keyboard then [[24, 1.0], [19, 0.6], [15, 0.3]]
                 when :strings  then [[15, 1.0], [12, 0.7], [7, 0.4]]
                 else [[15, 1.0], [12, 0.5], [7, 0.2]]
                 end

    { value: interval, score: score_value(interval, thresholds) }
  end

  def score_chromatic
    ratio = @score.chromatic_ratio
    return nil unless ratio

    { value: ratio, score: score_value(ratio, [[0.2, 1.0], [0.1, 0.7], [0.05, 0.4]]) }
  end

  def score_range
    semitones = @score.ambitus_semitones
    return nil unless semitones

    thresholds = case @instrument
                 when :guitar then [[40, 1.0], [36, 0.5], [30, 0.3], [27, 0.15]]
                 else [[24, 1.0], [18, 0.6], [12, 0.3]]
                 end

    { value: semitones, score: score_value(semitones, thresholds) }
  end

  def score_leap
    freq = @metrics.leap_frequency
    return nil unless freq

    { value: freq, score: score_value(freq, [[0.3, 1.0], [0.2, 0.7], [0.1, 0.4]]) }
  end

  # Helper: find score from threshold table [[threshold, score], ...]
  def score_value(value, thresholds)
    thresholds.each do |threshold, score|
      return score if value >= threshold
    end
    0.0
  end

  def ratio_to_difficulty(achieved, max_possible)
    return 1 if max_possible <= 0

    ratio = achieved / max_possible
    case ratio
    when 0.8.. then 5
    when 0.6.. then 4
    when 0.4.. then 3
    when 0.2.. then 2
    else 1
    end
  end
end
