# Cleanup normalization schema for consistent status tracking across all normalized fields.
#
# Changes:
# - Rename normalization_status → composer_status (clarity)
# - Rename genres → genre (singular, will hold clean value)
# - Drop normalized_genre (redundant, genre field will hold clean value)
# - Drop period_source (not needed, status enum is sufficient)
# - Add genre_status, period_status, instruments_status enums
#
# All status enums use: pending | normalized | not_applicable | failed
#
class CleanupNormalizationSchema < ActiveRecord::Migration[8.1]
  def change
    # 1. Rename normalization_status → composer_status
    rename_column :scores, :normalization_status, :composer_status

    # 2. Rename genres → genre (singular)
    rename_column :scores, :genres, :genre

    # 3. Drop redundant columns
    remove_column :scores, :normalized_genre, :string
    remove_column :scores, :period_source, :string

    # 4. Add status enums for genre, period, instruments
    add_column :scores, :genre_status, :string, default: "pending", null: false
    add_column :scores, :period_status, :string, default: "pending", null: false
    add_column :scores, :instruments_status, :string, default: "pending", null: false

    # 5. Add indexes for status columns (for querying pending records)
    add_index :scores, :genre_status
    add_index :scores, :period_status
    add_index :scores, :instruments_status
  end
end
