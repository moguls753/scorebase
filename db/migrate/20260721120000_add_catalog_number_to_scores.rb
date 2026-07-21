class AddCatalogNumberToScores < ActiveRecord::Migration[8.1]
  # Raw ALTER, not add_column: add_column rebuilds scores, dropping 6 FTS triggers + cascading score_pages.
  def up
    execute 'ALTER TABLE scores ADD COLUMN catalog_number varchar'
  end

  def down
    execute 'ALTER TABLE scores DROP COLUMN catalog_number'
  end
end
