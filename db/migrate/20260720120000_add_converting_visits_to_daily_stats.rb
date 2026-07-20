class AddConvertingVisitsToDailyStats < ActiveRecord::Migration[8.1]
  def change
    add_column :daily_stats, :converting_visits, :integer
  end
end
