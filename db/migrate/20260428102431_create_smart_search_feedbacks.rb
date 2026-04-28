class CreateSmartSearchFeedbacks < ActiveRecord::Migration[8.1]
  def change
    create_table :smart_search_feedbacks do |t|
      t.references :smart_search_query, null: false, foreign_key: { on_delete: :cascade }
      t.string  :ip_hash, null: false, limit: 64
      t.string  :verdict, null: false
      t.text    :comment

      t.datetime :created_at, null: false
    end

    add_index :smart_search_feedbacks, [:smart_search_query_id, :ip_hash],
      unique: true,
      name: "idx_one_feedback_per_query_per_visitor"
  end
end
