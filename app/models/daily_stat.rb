# == Schema Information
#
# Table name: daily_stats
#
#  id                  :integer          not null, primary key
#  browsers            :json
#  countries           :json
#  date                :date
#  devices             :json
#  paths               :json
#  referrers           :json
#  smd_clicks_by_score :json
#  user_agents         :json
#  visits              :integer          default(0)
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
# Indexes
#
#  index_daily_stats_on_date  (date) UNIQUE
#
class DailyStat < ApplicationRecord
  def total_smd_clicks
    (smd_clicks_by_score || {}).values.sum
  end

  # Roll up Ahoy data for `date` into a DailyStat row matching the dashboard's
  # JSON-column contract. Idempotent. Skipped entirely on days with no Ahoy
  # data so legacy/pre-cutover rows aren't clobbered with zeros.
  def self.aggregate_for!(date)
    range     = date.beginning_of_day..date.end_of_day
    visits    = Ahoy::Visit.where(started_at: range)
    events    = Ahoy::Event.where(time: range)
    pageviews = events.where(name: "$view")
    clicks    = events.where(name: "SMD click")

    return if pageviews.count.zero? && visits.count.zero?

    find_or_create_by(date: date).update!(
      visits:              pageviews.count,
      countries:           visits.where.not(country: nil).group(:country).count,
      referrers:           visits.group("COALESCE(NULLIF(referring_domain, ''), 'direct')").count,
      paths:               pageviews.group("json_extract(properties, '$.page')").count,
      devices:             visits.where.not(device_type: nil).group(:device_type).count,
      browsers:            visits.where.not(browser: nil).group(:browser).count,
      user_agents:         visits.where.not(user_agent: nil).group("substr(user_agent, 1, 100)").count,
      smd_clicks_by_score: clicks.group("json_extract(properties, '$.score_id')").count
    )
  end
end
