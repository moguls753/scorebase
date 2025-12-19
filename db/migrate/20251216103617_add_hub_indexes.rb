class AddHubIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :scores, :voicing
    add_index :scores, :genres
    add_index :scores, :instruments
  end
end
