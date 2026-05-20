class AddRagFailureReasonToScores < ActiveRecord::Migration[8.1]
  def change
    add_column :scores, :rag_failure_reason, :string, null: true
    add_index  :scores, :rag_failure_reason,
               where: "rag_failure_reason IS NOT NULL",
               name: "index_scores_on_rag_failure_reason_partial"
  end
end
