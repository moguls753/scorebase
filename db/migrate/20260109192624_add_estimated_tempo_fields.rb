# frozen_string_literal: true

class AddEstimatedTempoFields < ActiveRecord::Migration[8.0]
  def change
    add_column :scores, :estimated_tempo_bpm, :integer
    add_column :scores, :estimated_duration_seconds, :float
  end
end
