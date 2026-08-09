class AddSmdPageVisitsToDailyStats < ActiveRecord::Migration[8.1]
  def change
    add_column :daily_stats, :smd_page_visits, :integer
  end
end
