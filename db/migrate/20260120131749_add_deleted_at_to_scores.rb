class AddDeletedAtToScores < ActiveRecord::Migration[8.1]
  def change
    add_column :scores, :deleted_at, :datetime
    add_index :scores, :deleted_at
  end
end
