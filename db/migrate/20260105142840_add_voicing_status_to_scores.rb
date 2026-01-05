class AddVoicingStatusToScores < ActiveRecord::Migration[8.1]
  def change
    add_column :scores, :voicing_status, :string, default: "pending", null: false
    add_index :scores, :voicing_status
  end
end
