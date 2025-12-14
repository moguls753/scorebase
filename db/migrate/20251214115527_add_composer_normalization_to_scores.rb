class AddComposerNormalizationToScores < ActiveRecord::Migration[8.1]
  def change
    # Two-boolean system for composer normalization state tracking:
    #
    # composer_normalized: Did we successfully find a valid composer name?
    # composer_attempted:  Did we try to normalize with AI?
    #
    # State matrix:
    # - attempted: false, normalized: false → Not yet processed
    # - attempted: true,  normalized: true  → Successfully normalized
    # - attempted: true,  normalized: false → Tried but couldn't identify composer
    #
    # This prevents:
    # - Infinite reprocessing of unknowns (wastes API quota)
    # - Losing ability to retry with better AI/prompts later

    add_column :scores, :composer_normalized, :boolean, default: false, null: false
    add_column :scores, :composer_attempted, :boolean, default: false, null: false

    add_index :scores, :composer_normalized
    add_index :scores, :composer_attempted
  end
end
