class AddScorePageDeletionLog < ActiveRecord::Migration[8.1]
  def up
    create_table :score_page_deletion_logs do |t|
      t.integer :score_page_id, null: false
      t.integer :score_id, null: false
      t.integer :page_number, null: false
      t.datetime :deleted_at, null: false
      t.string :source  # 'trigger' (delete_all/CASCADE) or 'callback' (destroy)
      t.text :context   # call stack when available
    end

    add_index :score_page_deletion_logs, :deleted_at
    add_index :score_page_deletion_logs, :score_id

    # SQLite trigger catches ALL deletions including delete_all and CASCADE
    execute <<-SQL
      CREATE TRIGGER log_score_page_deletion
      AFTER DELETE ON score_pages
      FOR EACH ROW
      BEGIN
        INSERT INTO score_page_deletion_logs (score_page_id, score_id, page_number, deleted_at, source)
        VALUES (OLD.id, OLD.score_id, OLD.page_number, datetime('now'), 'trigger');
      END;
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS log_score_page_deletion"
    drop_table :score_page_deletion_logs
  end
end
