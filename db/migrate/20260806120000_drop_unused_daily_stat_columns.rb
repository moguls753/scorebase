class DropUnusedDailyStatColumns < ActiveRecord::Migration[8.1]
  def change
    remove_column :daily_stats, :converting_visits, :integer
    remove_column :daily_stats, :cross_link_visits_by_score, :json, default: "{}"
    remove_column :daily_stats, :browsers, :json
    remove_column :daily_stats, :user_agents, :json
    remove_column :daily_stats, :returning_rates, :json
  end
end
