# frozen_string_literal: true

# Generates descriptive labels for RAG search from raw score data.
# These labels help the LLM describe pieces naturally.
#
# Usage:
#   labeler = ScoreLabeler.new(score)
#   labeler.articulation_style  # "legato"
#   labeler.suitable_for        # ["sight-reading", "beginner"]
#
class ScoreLabeler
  def initialize(score)
    @score = score
    @metrics = ScoreMetricsCalculator.new(score)
  end

  # ─────────────────────────────────────────────────────────────────
  # Texture
  # ─────────────────────────────────────────────────────────────────

  # Based on voice independence metric (from parallel_motion analysis)
  def texture_type
    independence = @metrics.voice_independence
    return "monophonic" if (@score.num_parts || 1) == 1

    return nil unless independence

    case independence
    when 0.7.. then "polyphonic"
    when 0.3...0.7 then "mixed texture"
    else "homophonic"
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Articulation
  # ─────────────────────────────────────────────────────────────────

  def articulation_style
    return nil unless @score.slur_count && @score.event_count&.positive?

    slur_ratio = @score.slur_count.to_f / @score.event_count

    case slur_ratio
    when 0.5.. then "legato"
    when 0.2...0.5 then "mixed articulation"
    else "detached"
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Ornamentation
  # ─────────────────────────────────────────────────────────────────

  def ornamentation_level
    density = @metrics.ornament_density
    return nil unless density && density > 0

    case density
    when 0...0.3 then "lightly ornamented"
    when 0.3...1.0 then "moderately ornamented"
    else "heavily ornamented"
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Melodic character
  # ─────────────────────────────────────────────────────────────────

  def melodic_character
    stepwise = @metrics.stepwise_ratio
    leap_freq = @metrics.leap_frequency

    return nil unless stepwise || leap_freq

    if stepwise && stepwise > 0.7
      "smooth, stepwise melody"
    elsif leap_freq && leap_freq > 0.3
      "angular, disjunct melody"
    else
      "balanced melodic motion"
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Meter
  # ─────────────────────────────────────────────────────────────────

  def meter_label
    classification = @score.meter_classification
    beat_count = @score.beat_count
    time_sig = @score.time_signature

    parts = []

    if classification.present?
      parts << case classification
      when "compound" then "compound meter"
      when "simple" then "simple meter"
      when "complex" then "irregular meter"
      end
    end

    if beat_count
      parts << case beat_count
      when 2 then "in 2"
      when 3 then "in 3"
      when 4 then "in 4"
      when 6 then "in 6"
      end
    end

    parts.compact.join(", ").presence
  end

  # ─────────────────────────────────────────────────────────────────
  # Technical features
  # ─────────────────────────────────────────────────────────────────

  def technical_features
    features = []

    features << "requires pedal" if @score.has_pedal_marks
    features << "8va passages" if @score.has_ottava
    features << "trills" if @score.trill_count.to_i > 0
    features << "grace notes" if @score.grace_note_count.to_i > 0
    features << "tremolo" if @score.tremolo_count.to_i > 0
    features << "rolled chords" if @score.arpeggio_mark_count.to_i > 0

    features
  end

  # ─────────────────────────────────────────────────────────────────
  # Mode/Tonality
  # ─────────────────────────────────────────────────────────────────

  def mode_label
    return nil unless @score.detected_mode.present?

    case @score.detected_mode
    when "dorian" then "Dorian mode"
    when "phrygian" then "Phrygian mode"
    when "lydian" then "Lydian mode"
    when "mixolydian" then "Mixolydian mode"
    when "aeolian" then "Aeolian mode"
    when "locrian" then "Locrian mode"
    else nil
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Suitability
  # ─────────────────────────────────────────────────────────────────

  def suitable_for
    tags = []
    difficulty = DifficultyCalculator.new(@score).compute

    # Sight-reading: short, not too difficult
    if difficulty <= 2 && @score.duration_seconds.to_i < 180
      tags << "sight-reading"
    end

    # Beginner pieces
    tags << "beginner" if difficulty == 1

    # Teaching pieces (clear pedagogical value)
    if difficulty.in?(2..3) && has_pedagogical_focus?
      tags << "teaching piece"
    end

    # Exam repertoire
    tags << "exam repertoire" if difficulty.in?(3..4)

    # Competition/recital pieces
    if difficulty >= 4 && has_virtuoso_traits?
      tags << "recital piece"
    end

    tags
  end

  # ─────────────────────────────────────────────────────────────────
  # All labels as hash
  # ─────────────────────────────────────────────────────────────────

  def all
    {
      texture_type: texture_type,
      articulation_style: articulation_style,
      ornamentation_level: ornamentation_level,
      melodic_character: melodic_character,
      meter_label: meter_label,
      mode_label: mode_label,
      technical_features: technical_features,
      suitable_for: suitable_for
    }.compact_blank
  end

  private

  def has_pedagogical_focus?
    # Clear structure, limited range, accessible rhythms
    variety = @metrics.rhythmic_variety || 0
    variety < 0.5 && (@score.ambitus_semitones || 0) < 20
  end

  def has_virtuoso_traits?
    throughput = @metrics.throughput || 0
    ornament_density = @metrics.ornament_density || 0

    throughput > 6 || ornament_density > 1.0 || @score.tremolo_count.to_i > 0
  end
end
