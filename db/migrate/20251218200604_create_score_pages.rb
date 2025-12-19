class CreateScorePages < ActiveRecord::Migration[8.1]
  def change
    create_table :score_pages do |t|
      t.references :score, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.integer :page_number, null: false

      t.timestamps
    end

    # Composite index serves both uniqueness and score_id lookups (leftmost prefix)
    # Covers: WHERE score_id = ? ORDER BY page_number
    add_index :score_pages, [:score_id, :page_number], unique: true
  end
end
