class AddLastCrawledAtAndRenameSearchColumns < ActiveRecord::Migration[8.1]
  # Two changes in one migration so production pays for one lock, not two.
  #
  # 1. last_crawled_at — updated_at bumps on every save (normalizers, nightly
  #    group-key backfill), so it cannot answer "when did we last fetch this from
  #    the source". SmdRefreshJob orders by this column to stay resumable.
  #
  # 2. title_normalized -> title_search_normalized (and composer likewise).
  #    "normalized" was overloaded: NormalizeComposersJob rewrites `composer`
  #    into ScoreBase's "Last, First" convention, while these columns only strip
  #    accents so "Dvorak" finds "Dvořák". The old names read as though they held
  #    the convention-normalized name.
  #
  # Raw SQL rather than rename_column/add_column on purpose. Rails' SQLite
  # rename_column copies the whole table — measured ~50s per column on 448k rows,
  # and SQLite locks database-wide, so that is ~2min of blocked writes app-wide.
  # SQLite has supported native RENAME COLUMN since 3.25 (we run 3.53): it is a
  # metadata-only change measured at 3ms, and it rewrites references inside
  # triggers and indexes for us. That is also why this migration does NOT need
  # the usual drop-and-recreate of the six FTS triggers — verified they survive
  # intact, still pointing at the renamed columns.
  def up
    execute "ALTER TABLE scores ADD COLUMN last_crawled_at datetime(6)"
    add_index :scores, [ :source, :last_crawled_at ]

    rename_search_column("title_normalized", "title_search_normalized")
    rename_search_column("composer_normalized", "composer_search_normalized")
  end

  def down
    rename_search_column("title_search_normalized", "title_normalized")
    rename_search_column("composer_search_normalized", "composer_normalized")

    # Native DROP COLUMN refuses while an index references the column.
    remove_index :scores, [ :source, :last_crawled_at ]
    execute "ALTER TABLE scores DROP COLUMN last_crawled_at"
  end

  private

  # SQLite updates the column reference inside dependent indexes, but keeps their
  # old *names*, so rename those explicitly to stop the schema reading as a lie.
  def rename_search_column(from, to)
    execute "ALTER TABLE scores RENAME COLUMN #{from} TO #{to}"
    execute "DROP INDEX IF EXISTS index_scores_on_#{from}"
    execute "CREATE INDEX index_scores_on_#{to} ON scores (#{to})"
  end
end
