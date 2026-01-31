class AddUserAgentsToDailyStats < ActiveRecord::Migration[8.1]
  def change
    add_column :daily_stats, :user_agents, :json
  end
end
