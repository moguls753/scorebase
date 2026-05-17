class AddReturningRatesToDailyStats < ActiveRecord::Migration[8.1]
  def change
    add_column :daily_stats, :returning_rates, :json
  end
end
