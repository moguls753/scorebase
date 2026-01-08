class RenamePolyphonicDensityToVerticalDensity < ActiveRecord::Migration[8.1]
  def change
    rename_column :scores, :polyphonic_density, :vertical_density
  end
end
