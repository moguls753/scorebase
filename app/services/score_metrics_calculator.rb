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
  # Uses estimated_duration_seconds as fallback when duration_seconds is nil
  def throughput
    duration = effective_duration
    return nil unless @score.event_count && duration&.positive?
    (@score.event_count.to_f / duration).round(2)
  end

  # Effective duration: prefer Python-calculated, fall back to Ruby-estimated
  #
  # Duration formula: total_quarter_length / (tempo_bpm * tempo_referent) * 60
  #
  # - Python calculates duration_seconds when metronome mark exists (includes referent)
  # - Ruby calculates estimated_duration_seconds from text tempo (assumes quarter note referent)
  def effective_duration
    @score.duration_seconds || @score.estimated_duration_seconds
  end

  # Effective tempo: prefer metronome mark, fall back to estimated from text
  #
  # - tempo_bpm: from MusicXML metronome mark (e.g., quarter = 120)
  # - estimated_tempo_bpm: from tempo marking text (e.g., "Allegro" → 130)
  def effective_tempo
    @score.tempo_bpm || @score.estimated_tempo_bpm
  end

  # Effective referent: the beat unit the tempo refers to (in quarterLength)
  #
  # - 1.0 = quarter note
  # - 1.5 = dotted quarter
  # - 0.5 = eighth note
  # - 2.0 = half note
  #
  # Returns nil if using estimated tempo (assumes quarter note)
  def effective_referent
    @score.tempo_referent
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

  # Voice independence - from contrary motion of outer voices
  # Higher = more independent voice leading (polyphonic)
  # Based on contrary_motion_ratio extracted from Python
  def voice_independence
    @score.contrary_motion_ratio
  end

  # Vertical density - average simultaneous notes / parts
  # Higher = thicker texture
  def vertical_density
    return nil unless @score.simultaneous_note_avg && @score.num_parts&.positive?
    (@score.simultaneous_note_avg.to_f / @score.num_parts).round(3)
  end

  # TODO: Future enhancement - detect modal tendencies (dorian, phrygian, etc.)
  # Uses pitch_class_distribution + key_signature. See docs/refactor_todo.md Finding 3.
  def mode_tendency
    nil
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
