class AddVisitorHashToAhoyVisits < ActiveRecord::Migration[8.1]
  def change
    add_column :ahoy_visits, :visitor_hash,      :string, limit: 64
    add_column :ahoy_visits, :visitor_hash_next, :string, limit: 64
  end
end
