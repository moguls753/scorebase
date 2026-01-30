class AddCompositeIndexForActiveScoresSorting < ActiveRecord::Migration[8.1]
  def change
    # Partial index for active scores sorted by newest
    # Allows: SELECT * FROM scores WHERE deleted_at IS NULL ORDER BY created_at DESC
    # to use index directly without temp B-tree sort
    add_index :scores, :created_at, order: :desc,
              where: "deleted_at IS NULL",
              name: "index_scores_active_by_created_at"
  end
end
