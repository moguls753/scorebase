class AddGroupKeyToScores < ActiveRecord::Migration[8.1]
  def change
    add_column :scores, :group_key, :string
    add_index :scores, :group_key
  end
end
