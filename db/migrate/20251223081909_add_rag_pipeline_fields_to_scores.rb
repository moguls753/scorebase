class AddRagPipelineFieldsToScores < ActiveRecord::Migration[8.1]
  def change
    # RAG Pipeline status tracking
    add_column :scores, :rag_status, :string, default: "pending", null: false
    add_column :scores, :search_text, :text
    add_column :scores, :search_text_generated_at, :datetime
    add_column :scores, :indexed_at, :datetime
    add_column :scores, :index_version, :integer

    # Data enrichment fields
    add_column :scores, :period, :string
    add_column :scores, :period_source, :string
    add_column :scores, :normalized_genre, :string

    # Indexes for efficient querying
    add_index :scores, :rag_status
    add_index :scores, :indexed_at
    add_index :scores, :period
  end
end
