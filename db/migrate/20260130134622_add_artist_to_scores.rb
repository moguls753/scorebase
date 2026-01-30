class AddArtistToScores < ActiveRecord::Migration[8.1]
  def change
    add_column :scores, :artist, :string
    add_index :scores, :artist
  end
end
