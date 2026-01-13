class AddNormalizedSearchColumnsToScores < ActiveRecord::Migration[8.1]
  def change
    add_column :scores, :title_normalized, :string
    add_column :scores, :composer_normalized, :string
    add_index :scores, :title_normalized
    add_index :scores, :composer_normalized

    reversible do |dir|
      dir.up do
        # Backfill normalized columns
        Score.find_each do |score|
          score.update_columns(
            title_normalized: normalize(score.title),
            composer_normalized: normalize(score.composer)
          )
        end
      end
    end
  end

  private

  def normalize(text)
    return "" if text.blank?
    text.unicode_normalize(:nfkd).gsub(/\p{M}/, "")
  end
end
