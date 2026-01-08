# frozen_string_literal: true

# Phase 0 of extract.py refactor: add new raw music21 extraction fields.
# These raw counts let Ruby compute derived metrics (previously in Python).
class AddRawExtractionFieldsForRefactor < ActiveRecord::Migration[8.0]
  def change
    change_table :scores, bulk: true do |t|
      # New Phase 0 extractions
      t.integer :chromatic_note_count    # Notes outside the key signature
      t.string :meter_classification     # simple/compound/complex
      t.integer :beat_count              # Conducted beats (6/8 = 2)
      t.integer :voice_count             # Actual polyphonic voices
      t.boolean :has_pedal_marks         # Piano pedal markings
      t.integer :slur_count              # For legato calculation
      t.boolean :has_ottava              # 8va passages
      t.integer :trill_count             # Ornament counts
      t.integer :mordent_count
      t.integer :turn_count
      t.integer :tremolo_count
      t.integer :grace_note_count
      t.integer :arpeggio_mark_count
      t.json :modulation_targets         # List of key changes
      t.string :detected_mode            # dorian, phrygian, etc.

      # Raw fields for Ruby metric calculations
      t.integer :unique_duration_count   # For rhythmic_variety
      t.integer :off_beat_count          # For syncopation_level
      t.integer :chord_count             # For harmonic_rhythm
      t.integer :interval_count          # For stepwise_ratio
      t.integer :stepwise_count          # For stepwise_ratio
      t.float :simultaneous_note_avg     # For vertical_density
      t.integer :texture_chord_count     # For voice_independence
      t.integer :parallel_motion_count   # For voice_independence
    end
  end
end
