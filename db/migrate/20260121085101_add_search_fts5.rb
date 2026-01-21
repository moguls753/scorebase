# frozen_string_literal: true

class AddSearchFts5 < ActiveRecord::Migration[8.1]
  def up
    execute <<-SQL
      -- Create FTS5 virtual table for title/composer/genre search
      -- Trigram tokenizer enables substring matching (like LIKE '%sonata%')
      CREATE VIRTUAL TABLE scores_search_fts USING fts5(
        title,
        composer,
        genre,
        content='',
        tokenize='trigram'
      );
    SQL

    execute <<-SQL
      -- Populate with existing data (excluding soft-deleted scores)
      -- Uses normalized columns for accent-insensitive search
      INSERT INTO scores_search_fts(rowid, title, composer, genre)
      SELECT id,
             COALESCE(LOWER(title_normalized), ''),
             COALESCE(LOWER(composer_normalized), ''),
             COALESCE(LOWER(genre), '')
      FROM scores
      WHERE deleted_at IS NULL;
    SQL

    execute <<-SQL
      -- Trigger: After INSERT
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
      -- Trigger: After DELETE
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
      -- Trigger: After UPDATE
      CREATE TRIGGER scores_search_fts_au AFTER UPDATE ON scores
      BEGIN
        -- Remove old entry if it was in FTS
        INSERT INTO scores_search_fts(scores_search_fts, rowid, title, composer, genre)
        SELECT 'delete', OLD.id,
               COALESCE(LOWER(OLD.title_normalized), ''),
               COALESCE(LOWER(OLD.composer_normalized), ''),
               COALESCE(LOWER(OLD.genre), '')
        WHERE OLD.deleted_at IS NULL;

        -- Add new entry if should be in FTS
        INSERT INTO scores_search_fts(rowid, title, composer, genre)
        SELECT NEW.id,
               COALESCE(LOWER(NEW.title_normalized), ''),
               COALESCE(LOWER(NEW.composer_normalized), ''),
               COALESCE(LOWER(NEW.genre), '')
        WHERE NEW.deleted_at IS NULL;
      END;
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS scores_search_fts_au"
    execute "DROP TRIGGER IF EXISTS scores_search_fts_ad"
    execute "DROP TRIGGER IF EXISTS scores_search_fts_ai"
    execute "DROP TABLE IF EXISTS scores_search_fts"
  end
end
