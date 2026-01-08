class RenamePositionShiftColumnsToLeap < ActiveRecord::Migration[8.1]
  def change
    rename_column :scores, :position_shift_count, :leap_count
    rename_column :scores, :position_shifts_per_measure, :leaps_per_measure
  end
end
