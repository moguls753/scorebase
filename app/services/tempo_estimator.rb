# frozen_string_literal: true

# Estimates tempo BPM from tempo marking text.
#
# Supports Italian, German, and French tempo terms.
# Returns midpoint of standard tempo ranges.
#
# Usage:
#   TempoEstimator.estimate("Allegro")           # => 130
#   TempoEstimator.estimate("Andante con moto")  # => 95 (matches "Andante")
#   TempoEstimator.estimate("Langsam")           # => 50 (German)
#   TempoEstimator.estimate("Unknown text")      # => nil
#
class TempoEstimator
  # Tempo ranges (BPM) - using midpoint of standard ranges
  # Ordered from slowest to fastest within each language
  #
  # Sources: Harvard Dictionary of Music, Grove Music Online
  # IMPORTANT: Order matters! Longer/more specific patterns must come first.
  # "Larghetto" must match before "Largo", "Prestissimo" before "Presto", etc.
  TEMPO_TERMS = {
    # Italian - ordered by specificity (longer forms first)
    /\bgravissimo\b/i => 35,
    /\bgrave\b/i => 40,
    /\blarghetto\b/i => 60,      # before largo
    /\blargo\b/i => 50,
    /\blento\b/i => 55,
    /\badagietto\b/i => 75,      # before adagio
    /\badagio\b/i => 70,
    /\bandantino\b/i => 95,      # before andante
    /\bandante\b/i => 90,
    /\bmodera?to\b/i => 110,
    /\ballegretto\b/i => 115,    # before allegro
    /\ballegro\b/i => 130,
    /\bvivacissimo\b/i => 160,   # before vivace
    /\bvivace\b/i => 150,
    /\bprestissimo\b/i => 190,   # before presto
    /\bpresto\b/i => 170,

    # German - ordered by specificity
    /\bsehr langsam\b/i => 40,   # before langsam
    /\bsehr schnell\b/i => 170,  # before schnell
    /\blangsam\b/i => 50,
    /\bbreit\b/i => 50,
    /\bgetragen\b/i => 60,
    /\bmäßig\b/i => 100,
    /\bmassig\b/i => 100,
    /\bbewegt\b/i => 110,
    /\blebhaft\b/i => 130,
    /\brasch\b/i => 140,
    /\bschnell\b/i => 150,

    # French - ordered by specificity
    /\btrès lent\b/i => 40,      # before lent
    /\btrès vite\b/i => 180,     # before vite
    /\blentement\b/i => 50,      # before lent
    /\blent\b/i => 50,
    /\bmodéré\b/i => 110,
    /\bmodere\b/i => 110,
    /\banimé\b/i => 130,
    /\banime\b/i => 130,
    /\bvif\b/i => 150,
    /\bvite\b/i => 160
  }.freeze

  # Estimate BPM from tempo marking text
  #
  # @param marking [String, nil] tempo marking text (e.g., "Allegro ma non troppo")
  # @return [Integer, nil] estimated BPM or nil if no match
  def self.estimate(marking)
    return nil if marking.blank?

    # Try each pattern, return first match
    # Patterns are checked in definition order
    TEMPO_TERMS.each do |pattern, bpm|
      return bpm if marking.match?(pattern)
    end

    nil
  end

  # Check if a marking contains a recognized tempo term
  #
  # @param marking [String, nil] tempo marking text
  # @return [Boolean]
  def self.recognizes?(marking)
    estimate(marking).present?
  end

  # Return all matched tempo terms from a marking (for debugging)
  #
  # @param marking [String, nil] tempo marking text
  # @return [Array<String>] matched terms
  def self.matched_terms(marking)
    return [] if marking.blank?

    TEMPO_TERMS.keys.select { |pattern| marking.match?(pattern) }
               .map { |pattern| pattern.source.gsub(/\\b|\/i/, "") }
  end
end
