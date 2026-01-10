class AddIsMultiMovementToScores < ActiveRecord::Migration[8.1]
  def change
    add_column :scores, :is_multi_movement, :boolean
  end
end
