class AddIndexToHasVocalStatus < ActiveRecord::Migration[8.1]
  def change
    add_index :scores, :has_vocal_status
  end
end
