class AddSmdClicksByScoreToDailyStats < ActiveRecord::Migration[8.1]
  def change
    add_column :daily_stats, :smd_clicks_by_score, :json, default: {}
  end
end
