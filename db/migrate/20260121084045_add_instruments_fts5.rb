# frozen_string_literal: true

class AddInstrumentsFts5 < ActiveRecord::Migration[8.1]
  def up
    execute <<-SQL
      -- Create FTS5 virtual table with trigram tokenizer for substring matching
      -- This enables fast LIKE '%guitar%' style queries
      CREATE VIRTUAL TABLE scores_instruments_fts USING fts5(
        instruments,
        content='',
        tokenize='trigram'
      );
    SQL

    execute <<-SQL
      -- Populate with existing data (excluding soft-deleted scores)
      INSERT INTO scores_instruments_fts(rowid, instruments)
      SELECT id, LOWER(instruments)
      FROM scores
      WHERE instruments IS NOT NULL
        AND instruments != ''
        AND deleted_at IS NULL;
    SQL

    execute <<-SQL
      -- Trigger: After INSERT - add to FTS if has instruments and not deleted
      CREATE TRIGGER scores_instruments_fts_ai AFTER INSERT ON scores
      WHEN NEW.instruments IS NOT NULL AND NEW.instruments != '' AND NEW.deleted_at IS NULL
      BEGIN
        INSERT INTO scores_instruments_fts(rowid, instruments)
        VALUES (NEW.id, LOWER(NEW.instruments));
      END;
    SQL

    execute <<-SQL
      -- Trigger: After DELETE - remove from FTS
      CREATE TRIGGER scores_instruments_fts_ad AFTER DELETE ON scores
      WHEN OLD.instruments IS NOT NULL AND OLD.instruments != ''
      BEGIN
        INSERT INTO scores_instruments_fts(scores_instruments_fts, rowid, instruments)
        VALUES ('delete', OLD.id, LOWER(OLD.instruments));
      END;
    SQL

    execute <<-SQL
      -- Trigger: After UPDATE - handle all cases:
      -- 1. Instruments changed
      -- 2. Score soft-deleted (deleted_at set)
      -- 3. Score restored (deleted_at cleared)
      CREATE TRIGGER scores_instruments_fts_au AFTER UPDATE ON scores
      BEGIN
        -- Remove old entry if it existed in FTS
        INSERT INTO scores_instruments_fts(scores_instruments_fts, rowid, instruments)
        SELECT 'delete', OLD.id, LOWER(OLD.instruments)
        WHERE OLD.instruments IS NOT NULL
          AND OLD.instruments != ''
          AND OLD.deleted_at IS NULL;

        -- Add new entry if should be in FTS
        INSERT INTO scores_instruments_fts(rowid, instruments)
        SELECT NEW.id, LOWER(NEW.instruments)
        WHERE NEW.instruments IS NOT NULL
          AND NEW.instruments != ''
          AND NEW.deleted_at IS NULL;
      END;
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS scores_instruments_fts_au"
    execute "DROP TRIGGER IF EXISTS scores_instruments_fts_ad"
    execute "DROP TRIGGER IF EXISTS scores_instruments_fts_ai"
    execute "DROP TABLE IF EXISTS scores_instruments_fts"
  end
end
