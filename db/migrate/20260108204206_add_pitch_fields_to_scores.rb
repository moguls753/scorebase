class AddPitchFieldsToScores < ActiveRecord::Migration[8.1]
  def change
    # Rename for clarity:
    # - note_count → event_count (rhythmic events, chord = 1)
    # - chromatic_complexity → chromatic_ratio (computed in Python now)
    rename_column :scores, :note_count, :event_count
    rename_column :scores, :chromatic_complexity, :chromatic_ratio

    # New columns:
    # - pitch_count = individual pitches (chord with 4 notes = 4)
    # - pitch_class_distribution = histogram of pitch classes for mode detection
    add_column :scores, :pitch_count, :integer
    add_column :scores, :pitch_class_distribution, :json
  end
end
