class AddIndexToScoresCreatedAt < ActiveRecord::Migration[8.1]
  def change
    add_index :scores, :created_at
  end
end
