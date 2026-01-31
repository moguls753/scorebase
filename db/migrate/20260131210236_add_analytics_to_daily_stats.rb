class AddAnalyticsToDailyStats < ActiveRecord::Migration[8.1]
  def change
    add_column :daily_stats, :countries, :json
    add_column :daily_stats, :referrers, :json
    add_column :daily_stats, :paths, :json
    add_column :daily_stats, :devices, :json
    add_column :daily_stats, :browsers, :json
  end
end
