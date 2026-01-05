class AddHasVocalStatusToScores < ActiveRecord::Migration[8.1]
  def change
    add_column :scores, :has_vocal_status, :string, default: "pending", null: false
  end
end
