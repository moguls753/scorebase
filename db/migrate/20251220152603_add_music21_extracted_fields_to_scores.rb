# frozen_string_literal: true

# Adds comprehensive music21-extracted analysis fields to scores.
# These fields enable rich musical querying and RAG embeddings.
#
# Design decisions:
# - Many nullable fields are intentional: not all scores have MusicXML,
#   and not all fields can be extracted from every score.
# - JSON fields store complex per-part data (voice ranges, intervals)
# - Float fields normalized to 0.0-1.0 for complexity metrics
# - Extraction status tracks processing state for background jobs
#
class AddMusic21ExtractedFieldsToScores < ActiveRecord::Migration[8.1]
  def change
    change_table :scores, bulk: true do |t|
      # ─────────────────────────────────────────────────────────────────
      # PITCH & RANGE ANALYSIS
      # ─────────────────────────────────────────────────────────────────
      t.string  :highest_pitch           # e.g., "C6", "G5" - highest note in score
      t.string  :lowest_pitch            # e.g., "E2", "C3" - lowest note in score
      t.integer :ambitus_semitones       # Total pitch range in semitones (e.g., 24 = 2 octaves)
      t.json    :pitch_range_per_part    # {"Soprano": {"high": "G5", "low": "C4"}, ...}
      t.json    :voice_ranges            # {"Soprano": 14, "Alto": 12, ...} semitones per part

      # ─────────────────────────────────────────────────────────────────
      # TEMPO & DURATION
      # ─────────────────────────────────────────────────────────────────
      t.integer :tempo_bpm               # Detected or marked tempo (beats per minute)
      t.string  :tempo_marking           # e.g., "Allegro", "Andante con moto"
      t.float   :duration_seconds        # Estimated playback duration
      t.integer :measure_count           # Total number of measures

      # ─────────────────────────────────────────────────────────────────
      # COMPLEXITY METRICS
      # ─────────────────────────────────────────────────────────────────
      t.integer :note_count              # Total notes in score
      t.float   :note_density            # Average notes per measure
      t.integer :unique_pitches          # Count of distinct pitches used
      t.integer :accidental_count        # Count of accidentals (sharps/flats not in key)
      t.float   :chromatic_complexity    # 0.0-1.0 ratio of chromatic to diatonic movement

      # ─────────────────────────────────────────────────────────────────
      # RHYTHM ANALYSIS
      # ─────────────────────────────────────────────────────────────────
      t.json    :rhythm_distribution     # {"quarter": 45, "eighth": 30, "half": 15, ...}
      t.float   :syncopation_level       # 0.0-1.0 degree of syncopation
      t.float   :rhythmic_variety        # 0.0-1.0 variety of note durations used
      t.string  :predominant_rhythm      # Most common note value: "quarter", "eighth"

      # ─────────────────────────────────────────────────────────────────
      # HARMONY & KEY ANALYSIS
      # ─────────────────────────────────────────────────────────────────
      t.float   :key_confidence          # 0.0-1.0 confidence in detected key
      t.json    :key_correlations        # {"C major": 0.95, "A minor": 0.72, ...}
      t.text    :modulations             # Comma-separated key changes: "C major → G major → E minor"
      t.integer :modulation_count        # Number of key changes
      t.json    :chord_symbols           # ["I", "IV", "V7", "I"] Roman numeral analysis
      t.float   :harmonic_rhythm         # Chord changes per measure

      # ─────────────────────────────────────────────────────────────────
      # MELODIC ANALYSIS
      # ─────────────────────────────────────────────────────────────────
      t.json    :interval_distribution   # {"m2": 15, "M2": 25, "m3": 10, ...}
      t.integer :largest_interval        # Largest melodic leap in semitones
      t.float   :stepwise_motion_ratio   # 0.0-1.0 ratio of steps vs leaps
      t.string  :melodic_contour         # "ascending", "descending", "arch", "wave"
      t.float   :melodic_complexity      # 0.0-1.0 overall melodic complexity score

      # ─────────────────────────────────────────────────────────────────
      # STRUCTURAL ANALYSIS
      # ─────────────────────────────────────────────────────────────────
      t.string  :form_analysis           # Detected form: "ABA", "AABB", "through-composed"
      t.integer :sections_count          # Number of distinct sections
      t.integer :repeats_count           # Number of repeat signs
      t.text    :cadence_types           # Comma-separated: "PAC, IAC, HC, DC"
      t.string  :final_cadence           # Last cadence type: "PAC", "IAC", "plagal"

      # ─────────────────────────────────────────────────────────────────
      # NOTATION FEATURES
      # ─────────────────────────────────────────────────────────────────
      t.text    :clefs_used              # Comma-separated: "treble, bass, alto"
      t.boolean :has_dynamics            # Whether dynamic markings present
      t.string  :dynamic_range           # e.g., "pp-ff", "p-mf"
      t.boolean :has_articulations       # Staccato, legato, accents, etc.
      t.boolean :has_ornaments           # Trills, mordents, turns, etc.
      t.boolean :has_tempo_changes       # Ritardando, accelerando, etc.
      t.boolean :has_fermatas            # Fermata/pause markings
      t.text    :expression_markings     # "dolce, espressivo, cantabile"

      # ─────────────────────────────────────────────────────────────────
      # LYRICS & TEXT
      # ─────────────────────────────────────────────────────────────────
      t.boolean :has_extracted_lyrics    # Whether lyrics were found in MusicXML
      t.text    :extracted_lyrics        # Full lyrics text (for semantic search)
      t.integer :syllable_count          # Total syllables (for difficulty)
      t.string  :lyrics_language         # Detected language: "latin", "german", "english"

      # ─────────────────────────────────────────────────────────────────
      # INSTRUMENTATION (from score analysis)
      # ─────────────────────────────────────────────────────────────────
      t.text    :part_names              # Comma-separated: "Soprano, Alto, Tenor, Bass"
      t.text    :detected_instruments    # music21's instrument detection
      t.text    :instrument_families     # "voice, keyboard, strings"
      t.boolean :is_vocal                # Primary vocal content
      t.boolean :is_instrumental         # Primary instrumental content
      t.boolean :has_accompaniment       # Vocal with instrumental accompaniment

      # ─────────────────────────────────────────────────────────────────
      # TEXTURE & DENSITY
      # ─────────────────────────────────────────────────────────────────
      t.string  :texture_type            # "monophonic", "homophonic", "polyphonic", "heterophonic"
      t.float   :polyphonic_density      # 0.0-1.0 average simultaneous voices
      t.float   :voice_independence      # 0.0-1.0 how independent the voices are

      # ─────────────────────────────────────────────────────────────────
      # EXTRACTION STATUS & METADATA
      # ─────────────────────────────────────────────────────────────────
      t.string  :extraction_status, default: "pending", null: false
      t.text    :extraction_error        # Error message if extraction failed
      t.datetime :extracted_at           # When extraction was performed
      t.string  :music21_version         # Version used for extraction
      t.string  :musicxml_source         # "mxl", "xml", "musicxml" - original format
    end

    # ─────────────────────────────────────────────────────────────────
    # INDEXES for common queries
    # ─────────────────────────────────────────────────────────────────

    # Extraction job management
    add_index :scores, :extraction_status

    # Range queries (find pieces within vocal range)
    add_index :scores, :ambitus_semitones
    add_index :scores, :highest_pitch
    add_index :scores, :lowest_pitch

    # Duration/tempo filters
    add_index :scores, :duration_seconds
    add_index :scores, :tempo_bpm
    add_index :scores, :measure_count

    # Complexity filtering
    add_index :scores, :note_count
    add_index :scores, :chromatic_complexity
    add_index :scores, :melodic_complexity

    # Content type filtering
    add_index :scores, :has_extracted_lyrics
    add_index :scores, :is_vocal
    add_index :scores, :texture_type

    # Harmonic analysis
    add_index :scores, :key_confidence
    add_index :scores, :modulation_count
  end
end
