class RemoveSmdClicksFromDailyStats < ActiveRecord::Migration[8.1]
  def change
    remove_column :daily_stats, :smd_clicks, :integer
  end
end
