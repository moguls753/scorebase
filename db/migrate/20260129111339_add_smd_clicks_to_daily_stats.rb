class AddSmdClicksToDailyStats < ActiveRecord::Migration[8.1]
  def change
    add_column :daily_stats, :smd_clicks, :integer, default: 0
  end
end
