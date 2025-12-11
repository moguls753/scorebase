class AddMetadataFieldsToScores < ActiveRecord::Migration[8.1]
  def change
    add_column :scores, :language, :string
    add_column :scores, :instruments, :string
    add_column :scores, :voicing, :string
  end
end
