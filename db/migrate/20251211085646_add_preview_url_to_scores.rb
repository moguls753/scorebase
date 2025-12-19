class AddPreviewUrlToScores < ActiveRecord::Migration[8.1]
  def change
    add_column :scores, :preview_url, :string
  end
end
