class AddCompositeIndexOnPeriodAndDeletedAtToScores < ActiveRecord::Migration[8.1]
  def change
    add_index :scores, [:period, :deleted_at], name: "index_scores_on_period_and_deleted_at"
  end
end
