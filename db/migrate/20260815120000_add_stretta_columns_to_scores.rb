class AddStrettaColumnsToScores < ActiveRecord::Migration[8.1]
  # Everything the second commercial partner needs, in one lock.
  #
  # Raw ADD COLUMN, never Rails' add/rename/remove_column: the SQLite adapter
  # table-copies for those (~50s on 448k rows, database-wide lock), the copy
  # loses the six FTS triggers, and ON DELETE CASCADE takes every score_page
  # with it. Native ADD COLUMN is a metadata-only write.
  #
  # index_scores_on_source_and_external_id is the upsert_all conflict target.
  # Uniqueness is a model validation today, which a bulk write skips. Verified
  # on production data before writing this: GROUP BY source, external_id HAVING
  # count(*) > 1 returns zero rows (33,539 rows carry NULL external_id, which
  # SQLite permits any number of in a unique index).
  def up
    execute "ALTER TABLE scores ADD COLUMN price_eur decimal(8,2)"
    execute "ALTER TABLE scores ADD COLUMN original_price_eur decimal(8,2)"
    execute "ALTER TABLE scores ADD COLUMN group_rank integer"
    execute "ALTER TABLE scores ADD COLUMN work_key varchar"
    execute "ALTER TABLE scores ADD COLUMN duplicate_of_id integer"
    execute "ALTER TABLE scores ADD COLUMN available_for_sale boolean"
    execute "ALTER TABLE scores ADD COLUMN partner_slug varchar"
    execute "ALTER TABLE scores ADD COLUMN stretta_metadata json"

    add_index :scores, :work_key
    add_index :scores, :duplicate_of_id
    add_index :scores, [ :source, :external_id ], unique: true
  end

  def down
    remove_index :scores, [ :source, :external_id ]
    remove_index :scores, :duplicate_of_id
    remove_index :scores, :work_key

    %w[
      price_eur original_price_eur group_rank work_key duplicate_of_id
      available_for_sale partner_slug stretta_metadata
    ].each { |column| execute "ALTER TABLE scores DROP COLUMN #{column}" }
  end
end
