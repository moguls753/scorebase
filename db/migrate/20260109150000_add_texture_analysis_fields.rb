# frozen_string_literal: true

class AddTextureAnalysisFields < ActiveRecord::Migration[8.0]
  def change
    change_table :scores, bulk: true do |t|
      # New texture metrics from improved extraction
      t.float :texture_variation      # Std dev of notes per chord (texture consistency)
      t.float :avg_chord_span         # Average voicing width in semitones
      t.float :contrary_motion_ratio  # Outer voices moving opposite (0-1, polyphonic indicator)
      t.float :parallel_motion_ratio  # Outer voices moving same direction (0-1, homophonic indicator)
      t.float :oblique_motion_ratio   # One voice holds, other moves (0-1)
    end

    # Old columns to remove in future migration:
    # - texture_chord_count (redundant with chord_count)
    # - parallel_motion_count (replaced by parallel_motion_ratio)
  end
end
