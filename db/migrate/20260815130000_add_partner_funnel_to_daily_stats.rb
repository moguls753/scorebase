class AddPartnerFunnelToDailyStats < ActiveRecord::Migration[8.1]
  # The funnel columns were named for the only partner there was. Keyed by partner
  # instead, so "does Stretta earn anything" stays answerable and a third partner
  # costs no migration. daily_stats is 108 rows, so a Rails migration is fine here —
  # unlike on scores.
  def up
    add_column :daily_stats, :partner_page_visits, :json
    add_column :daily_stats, :partner_clicks_by_score, :json
    add_column :daily_stats, :partner_converting_visits, :json

    DailyStat.reset_column_information
    DailyStat.where.not(smd_page_visits: nil).find_each do |stat|
      stat.update_columns(
        partner_page_visits: { "smd" => stat.smd_page_visits },
        partner_clicks_by_score: { "smd" => stat.smd_clicks_by_score || {} },
        partner_converting_visits: { "smd" => stat.human_converting_visits.to_i }
      )
    end
  end

  def down
    remove_column :daily_stats, :partner_converting_visits
    remove_column :daily_stats, :partner_clicks_by_score
    remove_column :daily_stats, :partner_page_visits
  end
end
