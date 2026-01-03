class AddSearchCountResetAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :search_count_reset_at, :datetime
  end
end
