# frozen_string_literal: true

class AddTempoReferentFields < ActiveRecord::Migration[8.0]
  def change
    # tempo_referent: quarterLength of the beat unit (1.0 = quarter, 1.5 = dotted quarter)
    add_column :scores, :tempo_referent, :float

    # total_quarter_length: score duration in quarter note units (ground truth for duration calc)
    add_column :scores, :total_quarter_length, :float
  end
end
