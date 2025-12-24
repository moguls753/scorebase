class AddNewExtractionFields < ActiveRecord::Migration[8.1]
  def change
    # Computed difficulty (1-5) based on ALL complexity metrics
    add_column :scores, :computed_difficulty, :integer
    add_index :scores, :computed_difficulty

    # Hand span for piano/keyboard (semitones) - enables "small hands" queries
    add_column :scores, :max_chord_span, :integer

    # Average pitch per part (tessitura) - enables "comfortable for alto" queries
    # JSON: { "Soprano": { "average_pitch": "G4", "average_midi": 67.2 }, ... }
    add_column :scores, :tessitura, :json

    # Position shifts for instrumental difficulty
    add_column :scores, :position_shift_count, :integer
    add_column :scores, :position_shifts_per_measure, :float
  end
end
