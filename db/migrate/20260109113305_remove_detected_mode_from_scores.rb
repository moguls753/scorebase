class RemoveDetectedModeFromScores < ActiveRecord::Migration[8.1]
  def change
    remove_column :scores, :detected_mode, :string # always nil, music21 limitation
  end
end
