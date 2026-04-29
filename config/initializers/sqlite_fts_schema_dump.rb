# SQLite's `.schema` dump emits FTS5 shadow tables (e.g. `scores_search_fts_data`,
# `_fts_idx`, `_fts_docsize`, `_fts_config`) alongside the `CREATE VIRTUAL TABLE
# ... USING fts5(...)` statement that auto-creates them. Replaying the dump then
# fails because the virtual-table creation tries to create shadow tables that
# already exist, leaving the virtual table itself missing ("no such table:
# scores_search_fts" on every subsequent insert).
#
# Filter the shadow-table declarations out of structure.sql so only the
# CREATE VIRTUAL TABLE remains; SQLite recreates the shadow tables itself.

if defined?(ActiveRecord::Tasks::SQLiteDatabaseTasks)
  module SqliteFtsSchemaDump
    SHADOW_TABLE_RE = /\ACREATE TABLE IF NOT EXISTS ['"]?\w+_fts_(data|idx|docsize|config)['"]?/

    def structure_dump(filename, extra_flags)
      super
      lines = File.readlines(filename)
      File.write(filename, lines.reject { |l| l.match?(SHADOW_TABLE_RE) }.join)
    end
  end

  ActiveRecord::Tasks::SQLiteDatabaseTasks.prepend(SqliteFtsSchemaDump)
end
