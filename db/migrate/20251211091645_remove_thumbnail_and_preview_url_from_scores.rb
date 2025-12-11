class RemoveThumbnailAndPreviewUrlFromScores < ActiveRecord::Migration[8.1]
  def change
    remove_column :scores, :thumbnail_url, :string
    remove_column :scores, :preview_url, :string
  end
end
