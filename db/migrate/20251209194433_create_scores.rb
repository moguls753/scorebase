class CreateScores < ActiveRecord::Migration[8.1]
  def change
    create_table :scores do |t|
      t.string :title
      t.string :composer
      t.string :key_signature
      t.string :time_signature
      t.integer :num_parts
      t.text :genres
      t.text :tags
      t.integer :complexity
      t.decimal :rating, precision: 3, scale: 2
      t.integer :views, default: 0
      t.integer :favorites, default: 0
      t.string :thumbnail_url
      t.string :data_path
      t.string :metadata_path
      t.string :mxl_path
      t.string :pdf_path
      t.string :mid_path

      t.timestamps
    end

    # Add indexes for fast filtering and searching
    add_index :scores, :key_signature
    add_index :scores, :time_signature
    add_index :scores, :num_parts
    add_index :scores, :complexity
    add_index :scores, :rating
    add_index :scores, :views
    add_index :scores, :composer
  end
end
