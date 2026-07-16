class AddCrossLinkVisitsToDailyStats < ActiveRecord::Migration[8.1]
  def change
    add_column :daily_stats, :cross_link_visits_by_score, :json, default: {}
  end
end
