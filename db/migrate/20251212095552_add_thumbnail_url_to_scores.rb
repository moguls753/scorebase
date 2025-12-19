class AddThumbnailUrlToScores < ActiveRecord::Migration[8.1]
  def change
    add_column :scores, :thumbnail_url, :string
  end
end
