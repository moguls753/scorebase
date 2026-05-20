class RemoveRagFailureReasonFromScores < ActiveRecord::Migration[8.1]
  def change
    remove_column :scores, :rag_failure_reason, :string
  end
end
