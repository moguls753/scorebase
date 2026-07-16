class CreateScoreSmdMatches < ActiveRecord::Migration[8.1]
  def change
    create_table :score_smd_matches do |t|
      t.references :score, null: false, foreign_key: { to_table: :scores, on_delete: :cascade }
      t.references :smd_score, null: false, foreign_key: { to_table: :scores, on_delete: :cascade }
      t.integer :rank, null: false
      # Kill switch: suppressed rows survive the converge job and are excluded
      # from display, so a spotted false positive stays dead across recomputes.
      t.boolean :suppressed, null: false, default: false
      t.timestamps
    end

    add_index :score_smd_matches, [ :score_id, :smd_score_id ], unique: true
    add_index :score_smd_matches, [ :score_id, :rank ], unique: true, where: "suppressed = FALSE"
  end
end
