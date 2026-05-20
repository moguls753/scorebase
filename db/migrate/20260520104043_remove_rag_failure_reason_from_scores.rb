class RemoveRagFailureReasonFromScores < ActiveRecord::Migration[8.1]
  # SQLite's remove_column rewrites the scores table, which silently drops every
  # trigger defined ON scores -- including the 6 FTS sync triggers. Drop them
  # explicitly before the rewrite and recreate them after, so scores_search_fts
  # and scores_instruments_fts keep tracking writes. Both up and down do this;
  # otherwise a rollback would also nuke them. (Pattern: 20260517143000.)
  def up
    drop_fts_triggers
    remove_column :scores, :rag_failure_reason, :string
    create_fts_triggers
  end

  def down
    drop_fts_triggers
    add_column :scores, :rag_failure_reason, :string
    create_fts_triggers
  end

  private

  def drop_fts_triggers
    execute "DROP TRIGGER IF EXISTS scores_search_fts_ai"
    execute "DROP TRIGGER IF EXISTS scores_search_fts_ad"
    execute "DROP TRIGGER IF EXISTS scores_search_fts_au"
    execute "DROP TRIGGER IF EXISTS scores_instruments_fts_ai"
    execute "DROP TRIGGER IF EXISTS scores_instruments_fts_ad"
    execute "DROP TRIGGER IF EXISTS scores_instruments_fts_au"
  end

  def create_fts_triggers
    execute <<-SQL
      CREATE TRIGGER scores_search_fts_ai AFTER INSERT ON scores
      WHEN NEW.deleted_at IS NULL
      BEGIN
        INSERT INTO scores_search_fts(rowid, title, composer, genre)
        VALUES (
          NEW.id,
          COALESCE(LOWER(NEW.title_normalized), ''),
          COALESCE(LOWER(NEW.composer_normalized), ''),
          COALESCE(LOWER(NEW.genre), '')
        );
      END;
    SQL

    execute <<-SQL
      CREATE TRIGGER scores_search_fts_ad AFTER DELETE ON scores
      BEGIN
        INSERT INTO scores_search_fts(scores_search_fts, rowid, title, composer, genre)
        VALUES (
          'delete',
          OLD.id,
          COALESCE(LOWER(OLD.title_normalized), ''),
          COALESCE(LOWER(OLD.composer_normalized), ''),
          COALESCE(LOWER(OLD.genre), '')
        );
      END;
    SQL

    execute <<-SQL
      CREATE TRIGGER scores_search_fts_au AFTER UPDATE ON scores
      BEGIN
        INSERT INTO scores_search_fts(scores_search_fts, rowid, title, composer, genre)
        SELECT 'delete', OLD.id,
               COALESCE(LOWER(OLD.title_normalized), ''),
               COALESCE(LOWER(OLD.composer_normalized), ''),
               COALESCE(LOWER(OLD.genre), '')
        WHERE OLD.deleted_at IS NULL;

        INSERT INTO scores_search_fts(rowid, title, composer, genre)
        SELECT NEW.id,
               COALESCE(LOWER(NEW.title_normalized), ''),
               COALESCE(LOWER(NEW.composer_normalized), ''),
               COALESCE(LOWER(NEW.genre), '')
        WHERE NEW.deleted_at IS NULL;
      END;
    SQL

    execute <<-SQL
      CREATE TRIGGER scores_instruments_fts_ai AFTER INSERT ON scores
      WHEN NEW.instruments IS NOT NULL AND NEW.instruments != '' AND NEW.deleted_at IS NULL
      BEGIN
        INSERT INTO scores_instruments_fts(rowid, instruments)
        VALUES (NEW.id, LOWER(NEW.instruments));
      END;
    SQL

    execute <<-SQL
      CREATE TRIGGER scores_instruments_fts_ad AFTER DELETE ON scores
      WHEN OLD.instruments IS NOT NULL AND OLD.instruments != ''
      BEGIN
        INSERT INTO scores_instruments_fts(scores_instruments_fts, rowid, instruments)
        VALUES ('delete', OLD.id, LOWER(OLD.instruments));
      END;
    SQL

    execute <<-SQL
      CREATE TRIGGER scores_instruments_fts_au AFTER UPDATE ON scores
      BEGIN
        INSERT INTO scores_instruments_fts(scores_instruments_fts, rowid, instruments)
        SELECT 'delete', OLD.id, LOWER(OLD.instruments)
        WHERE OLD.instruments IS NOT NULL
          AND OLD.instruments != ''
          AND OLD.deleted_at IS NULL;

        INSERT INTO scores_instruments_fts(rowid, instruments)
        SELECT NEW.id, LOWER(NEW.instruments)
        WHERE NEW.instruments IS NOT NULL
          AND NEW.instruments != ''
          AND NEW.deleted_at IS NULL;
      END;
    SQL
  end
end
