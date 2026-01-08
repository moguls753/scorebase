# frozen_string_literal: true

# Computes interpretation metrics from raw extraction data.
# These are application-specific judgments, not musical facts.
#
# Facts (from Python): event_count, pitch_count, chromatic_ratio, etc.
# Interpretation (here): note_density, throughput, leap_frequency, etc.
#
# Usage:
#   metrics = ScoreMetricsCalculator.new(score)
#   metrics.throughput        # events per second
#   metrics.leap_frequency    # proportion of leaps vs steps
#
class ScoreMetricsCalculator
  def initialize(score)
    @score = score
  end

  # Events per second - actual speed demand
  # High throughput = fast passages
  def throughput
    return nil unless @score.event_count && @score.duration_seconds&.positive?
    (@score.event_count.to_f / @score.duration_seconds).round(2)
  end

  # Event density - events per measure
  # Useful for sight-reading difficulty
  def note_density
    return nil unless @score.event_count && @score.measure_count&.positive?
    (@score.event_count.to_f / @score.measure_count).round(2)
  end

  # Leap frequency - proportion of intervals > perfect 4th
  # Higher = more angular melody, harder for voice
  def leap_frequency
    return nil unless @score.leap_count && @score.event_count&.positive?
    (@score.leap_count.to_f / @score.event_count).round(3)
  end

  # Stepwise motion ratio - proportion of steps vs leaps
  # Higher = smoother melody, easier to sing
  def stepwise_ratio
    return nil unless @score.stepwise_count && @score.interval_count&.positive?
    (@score.stepwise_count.to_f / @score.interval_count).round(3)
  end

  # Ornament density - ornaments per measure
  # Higher = more technique demand
  def ornament_density
    total = [
      @score.trill_count,
      @score.mordent_count,
      @score.turn_count,
      @score.grace_note_count
    ].compact.sum

    return nil if total.zero? || !@score.measure_count&.positive?
    (total.to_f / @score.measure_count).round(2)
  end

  # Syncopation level - proportion of off-beat events
  def syncopation_level
    return nil unless @score.off_beat_count && @score.event_count&.positive?
    (@score.off_beat_count.to_f / @score.event_count).round(3)
  end

  # Rhythmic variety - normalized count of unique durations
  # 8 unique durations = max complexity
  def rhythmic_variety
    return nil unless @score.unique_duration_count
    [@score.unique_duration_count.to_f / 8.0, 1.0].min.round(3)
  end

  # Harmonic rhythm - chord changes per measure
  def harmonic_rhythm
    return nil unless @score.chord_count && @score.measure_count&.positive?
    (@score.chord_count.to_f / @score.measure_count).round(2)
  end

  # Voice independence - inverse of parallel motion
  # Higher = more independent voice leading (polyphonic)
  def voice_independence
    return nil unless @score.parallel_motion_count && @score.texture_chord_count
    return 0.0 if @score.texture_chord_count <= 1

    chord_transitions = @score.texture_chord_count - 1
    independence = 1.0 - (@score.parallel_motion_count.to_f / [chord_transitions, 49].min)
    independence.clamp(0.0, 1.0).round(3)
  end

  # Vertical density - average simultaneous notes / parts
  # Higher = thicker texture
  def vertical_density
    return nil unless @score.simultaneous_note_avg && @score.num_parts&.positive?
    (@score.simultaneous_note_avg.to_f / @score.num_parts).round(3)
  end

  # Compute all metrics as a hash
  # Note: chromatic_ratio comes from Python (fact), not calculated here
  def all
    {
      throughput: throughput,
      note_density: note_density,
      chromatic_ratio: @score.chromatic_ratio,
      leap_frequency: leap_frequency,
      stepwise_ratio: stepwise_ratio,
      ornament_density: ornament_density,
      syncopation_level: syncopation_level,
      rhythmic_variety: rhythmic_variety,
      harmonic_rhythm: harmonic_rhythm,
      voice_independence: voice_independence,
      vertical_density: vertical_density
    }.compact
  end
end
