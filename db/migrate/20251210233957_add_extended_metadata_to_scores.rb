class AddExtendedMetadataToScores < ActiveRecord::Migration[8.1]
  def change
    add_column :scores, :description, :text
    add_column :scores, :editor, :string
    add_column :scores, :license, :string
    add_column :scores, :lyrics, :text
    add_column :scores, :cpdl_number, :string
    add_column :scores, :posted_date, :date
    add_column :scores, :page_count, :integer
  end
end
