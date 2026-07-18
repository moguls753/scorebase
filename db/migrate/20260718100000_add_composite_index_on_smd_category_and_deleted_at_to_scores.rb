class AddCompositeIndexOnSmdCategoryAndDeletedAtToScores < ActiveRecord::Migration[8.1]
  def change
    add_index :scores, [:smd_category, :deleted_at], name: "index_scores_on_smd_category_and_deleted_at"
  end
end
