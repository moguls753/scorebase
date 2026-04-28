class CreateSmartSearchQueries < ActiveRecord::Migration[8.1]
  def change
    create_table :smart_search_queries do |t|
      t.text    :query,            null: false
      t.string  :query_type,       null: false
      t.references :parent_query,  foreign_key: { to_table: :smart_search_queries, on_delete: :nullify }, null: true
      t.string  :ip_hash,          null: false, limit: 64
      t.integer :result_count,     null: false, default: 0
      t.text    :score_ids,        null: false, default: "[]"
      t.text    :rag_summary
      t.text    :rag_recommendations
      t.integer :response_time_ms
      t.text    :error
      t.string  :locale,           null: false, limit: 2

      t.datetime :created_at, null: false
    end

    add_index :smart_search_queries, :created_at
    add_index :smart_search_queries, :ip_hash
    add_index :smart_search_queries, :parent_query_id,
      unique: true,
      where: "query_type = 'refinement'",
      name: "idx_one_refinement_per_parent"
    add_index :smart_search_queries, "LOWER(TRIM(query)), created_at",
      name: "idx_normalized_query_created_at"
  end
end
