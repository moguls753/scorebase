class AddSmartSearchCountToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :smart_search_count, :integer, default: 0, null: false
  end
end
