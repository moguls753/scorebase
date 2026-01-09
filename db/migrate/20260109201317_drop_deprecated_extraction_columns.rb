# frozen_string_literal: true

# Cleanup migration for deprecated extraction columns.
# See docs/refactor_todo.md for details on each finding.
class DropDeprecatedExtractionColumns < ActiveRecord::Migration[8.0]
  def change
    # Finding 2: voice_count always equals num_parts (music21 can't detect implicit polyphony)
    remove_column :scores, :voice_count, :integer

    # Finding 4: chord_symbols (Roman numeral analysis) was never used, expensive to compute
    remove_column :scores, :chord_symbols, :json

    # Finding 6: parallel_motion_count replaced by parallel_motion_ratio
    remove_column :scores, :parallel_motion_count, :integer

    # Finding 6: texture_chord_count redundant with chord_count
    remove_column :scores, :texture_chord_count, :integer
  end
end
