class RenameIsVocalToHasVocal < ActiveRecord::Migration[8.1]
  def change
    rename_column :scores, :is_vocal, :has_vocal
  end
end
