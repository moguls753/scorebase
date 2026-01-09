# frozen_string_literal: true

class AddUniqueChordCountToScores < ActiveRecord::Migration[8.0]
  def change
    add_column :scores, :unique_chord_count, :integer
  end
end
