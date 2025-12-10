class AddSourceToScores < ActiveRecord::Migration[8.1]
  def change
    add_column :scores, :source, :string, default: "pdmx"
    add_column :scores, :external_url, :string
    add_column :scores, :external_id, :string

    add_index :scores, :source
    add_index :scores, :external_id
  end
end
