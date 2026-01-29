# == Schema Information
#
# Table name: daily_stats
#
#  id                  :integer          not null, primary key
#  date                :date
#  smd_clicks_by_score :json
#  visits              :integer          default(0)
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
# Indexes
#
#  index_daily_stats_on_date  (date) UNIQUE
#
class DailyStat < ApplicationRecord
  def self.track_visit!
    daily_stat = find_or_create_by(date: Date.current)
    daily_stat.increment!(:visits)
  end

  def self.track_smd_click!(score_id:)
    return unless score_id.present?

    daily_stat = find_or_create_by(date: Date.current)
    clicks = daily_stat.smd_clicks_by_score || {}
    clicks[score_id.to_s] = (clicks[score_id.to_s] || 0) + 1
    daily_stat.update!(smd_clicks_by_score: clicks)
  end

  def total_smd_clicks
    (smd_clicks_by_score || {}).values.sum
  end
end
