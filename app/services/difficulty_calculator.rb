# frozen_string_literal: true

# Computes instrument-aware difficulty (1-5 scale).
#
# Same raw data means different things for different instruments:
# - chromatic_ratio 0.15: HARD for voice (no reference pitch), Easy for piano
# - leap_frequency 0.3: HARD for voice (breath, accuracy), Moderate for strings
# - max_chord_span 10: N/A for voice, Moderate for piano (9th stretch)
#
# Usage:
#   DifficultyCalculator.new(score).compute  # => 1..5
#
class DifficultyCalculator
  DIFFICULTY_LABELS = {
    1 => "beginner",
    2 => "easy",
    3 => "intermediate",
    4 => "advanced",
    5 => "expert"
  }.freeze

  def initialize(score)
    @score = score
    @metrics = ScoreMetricsCalculator.new(score)
    @instrument_type = infer_instrument_type
  end

  # Returns difficulty 1-5
  def compute
    points = case @instrument_type
    when :voice then vocal_points
    when :keyboard then keyboard_points
    when :strings then string_points
    when :guitar then guitar_points
    when :wind then wind_points
    else generic_points
    end

    points_to_difficulty(points)
  end

  # Returns label like "intermediate"
  def label
    DIFFICULTY_LABELS[compute]
  end

  private

  # Infer instrument type from score data
  def infer_instrument_type
    # Vocal scores
    return :voice if @score.has_vocal? || @score.voicing.present?

    instruments = @score.instruments.to_s.downcase

    # Keyboard
    return :keyboard if instruments.match?(/piano|organ|harpsichord|keyboard|clavichord/)

    # Strings
    return :strings if instruments.match?(/violin|viola|cello|bass|string quartet/)

    # Guitar
    return :guitar if instruments.match?(/guitar|lute|vihuela/)

    # Woodwinds/brass have similar considerations to strings (intonation matters)
    return :wind if instruments.match?(/flute|oboe|clarinet|bassoon|trumpet|horn|trombone|tuba/)

    :generic
  end

  def wind_points
    points = 0.0

    # Chromaticism = intonation difficulty (like strings)
    points += weight_chromatic * 2.0

    # Large intervals require embouchure/breath adjustments
    points += weight_interval * 1.5

    # Speed (tonguing/fingering)
    points += weight_throughput * 2.0

    # Ornaments (trills are fingering-dependent)
    points += weight_ornaments * 1.5

    # Range strain (high notes are harder)
    points += weight_range * 1.5

    points
  end

  # ─────────────────────────────────────────────────────────────────
  # Instrument-specific scoring
  # ─────────────────────────────────────────────────────────────────

  def vocal_points
    points = 0.0

    # Chromaticism is VERY hard for voice (no physical reference pitch)
    points += weight_chromatic * 3.0

    # Leaps require breath control and pitch memory
    points += weight_leap * 2.5

    # Range pushing tessitura limits
    points += weight_range * 2.0

    # Large intervals are hard to pitch accurately
    points += weight_interval * 2.0

    # Speed matters less for voice
    points += weight_throughput * 1.0

    # Ornamentation (melismatic passages)
    points += weight_ornaments * 1.5

    points
  end

  def keyboard_points
    points = 0.0

    # Speed (throughput) is primary difficulty for keyboard
    points += weight_throughput * 2.5

    # Hand span requirements
    points += weight_chord_span * 2.5

    # Voice count (counterpoint complexity)
    points += weight_voice_count * 2.0

    # Chromaticism is less relevant (just more black keys)
    points += weight_chromatic * 0.5

    # Ornaments (trills, mordents)
    points += weight_ornaments * 1.5

    # Large intervals = hand jumps
    points += weight_interval * 1.0

    points
  end

  def string_points
    points = 0.0

    # Chromaticism = intonation difficulty
    points += weight_chromatic * 2.5

    # Large intervals often mean position shifts
    points += weight_interval * 2.0

    # Double/triple stops (multi-voice writing)
    points += weight_voice_count * 2.0 if @score.voice_count.to_i > 1

    # Speed matters
    points += weight_throughput * 1.5

    # Ornaments (especially trills on strings)
    points += weight_ornaments * 1.5

    points
  end

  def guitar_points
    points = 0.0

    # Chord span (fret stretches)
    points += weight_chord_span * 2.0

    # Voice count (fingerpicking complexity)
    points += weight_voice_count * 2.0

    # Speed
    points += weight_throughput * 1.5

    # Large intervals (position shifts)
    points += weight_interval * 1.5

    # Chromaticism (fret navigation)
    points += weight_chromatic * 1.0

    points
  end

  def generic_points
    points = 0.0

    # Balanced weighting for unknown instruments
    points += weight_throughput * 1.5
    points += weight_chromatic * 1.5
    points += weight_interval * 1.5
    points += weight_leap * 1.5
    points += weight_ornaments * 1.0
    points += weight_voice_count * 1.0

    points
  end

  # ─────────────────────────────────────────────────────────────────
  # Weight calculations (0.0-1.0 normalized)
  # ─────────────────────────────────────────────────────────────────

  def weight_chromatic
    ratio = @metrics.chromatic_ratio || 0
    case ratio
    when 0.2.. then 1.0
    when 0.1.. then 0.7
    when 0.05.. then 0.4
    else 0.0
    end
  end

  def weight_leap
    freq = @metrics.leap_frequency || 0
    case freq
    when 0.3.. then 1.0
    when 0.2.. then 0.7
    when 0.1.. then 0.4
    else 0.0
    end
  end

  def weight_throughput
    rate = @metrics.throughput || 0
    case rate
    when 8.. then 1.0    # 8+ notes/sec = virtuosic
    when 5.. then 0.7
    when 3.. then 0.4
    else 0.0
    end
  end

  def weight_interval
    interval = @score.largest_interval || 0
    case interval
    when 12.. then 1.0   # Octave or larger
    when 7.. then 0.6    # 5th or larger
    when 5.. then 0.3
    else 0.0
    end
  end

  def weight_range
    semitones = @score.ambitus_semitones || 0
    case semitones
    when 24.. then 1.0   # 2+ octaves
    when 18.. then 0.6   # 1.5 octaves
    when 12.. then 0.3   # 1 octave
    else 0.0
    end
  end

  def weight_chord_span
    span = @score.max_chord_span || 0
    case span
    when 12.. then 1.0   # 10th or larger (very large hands)
    when 10.. then 0.7   # 9th (moderate stretch)
    when 8.. then 0.3    # Octave
    else 0.0
    end
  end

  def weight_voice_count
    count = @score.voice_count || @score.num_parts || 1
    case count
    when 4.. then 1.0
    when 3 then 0.6
    when 2 then 0.3
    else 0.0
    end
  end

  def weight_ornaments
    density = @metrics.ornament_density || 0
    case density
    when 1.5.. then 1.0
    when 0.5.. then 0.6
    when 0.1.. then 0.3
    else 0.0
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Score to difficulty mapping
  # ─────────────────────────────────────────────────────────────────

  def points_to_difficulty(points)
    # Max possible points varies by instrument, but roughly 10-12
    # Map to 1-5 scale
    case points
    when 0..2 then 1
    when 2..4 then 2
    when 4..6 then 3
    when 6..8 then 4
    else 5
    end
  end
end
