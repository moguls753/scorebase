class AddHumanVisitMetricsToDailyStats < ActiveRecord::Migration[8.1]
  def change
    add_column :daily_stats, :human_visits, :integer
    add_column :daily_stats, :human_converting_visits, :integer
  end
end
