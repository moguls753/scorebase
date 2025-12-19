class ConvertComposerNormalizationToEnum < ActiveRecord::Migration[8.1]
  def up
    add_column :scores, :normalization_status, :string, default: "pending", null: false

    # Migrate existing data
    execute <<-SQL
      UPDATE scores SET normalization_status = 'normalized'
      WHERE composer_attempted = true AND composer_normalized = true
    SQL
    execute <<-SQL
      UPDATE scores SET normalization_status = 'failed'
      WHERE composer_attempted = true AND composer_normalized = false
    SQL

    remove_column :scores, :composer_attempted
    remove_column :scores, :composer_normalized
    add_index :scores, :normalization_status
  end

  def down
    add_column :scores, :composer_normalized, :boolean, default: false, null: false
    add_column :scores, :composer_attempted, :boolean, default: false, null: false

    execute <<-SQL
      UPDATE scores SET composer_normalized = true, composer_attempted = true
      WHERE normalization_status = 'normalized'
    SQL
    execute <<-SQL
      UPDATE scores SET composer_normalized = false, composer_attempted = true
      WHERE normalization_status = 'failed'
    SQL

    remove_index :scores, :normalization_status
    remove_column :scores, :normalization_status
  end
end
