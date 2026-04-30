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
  # Hosts that count as "internal" — a visit referred from one of these is
  # someone navigating between pages on our own site, not a fresh arrival.
  # Configurable via ENV so dev/staging/prod can each provide their own host
  # list (e.g. "scorebase.org,localhost,staging.scorebase.org").
  INTERNAL_HOSTS = ENV.fetch("INTERNAL_ANALYTICS_HOSTS", "scorebase.org")
                      .split(",").map(&:strip).reject(&:empty?).freeze

  def total_smd_clicks
    (smd_clicks_by_score || {}).values.sum
  end

  # Roll up Ahoy data for `date` into a DailyStat row matching the dashboard's
  # JSON-column contract. Idempotent. Skipped entirely on days with no Ahoy
  # data so legacy/pre-cutover rows aren't clobbered with zeros.
  #
  # `visits` (and visit-derived breakdowns: countries, browsers, devices,
  # user_agents, referrers) count *external arrivals only* — visits whose
  # referring_domain is NULL (direct entry) or not one of INTERNAL_HOSTS.
  # `paths` and `smd_clicks_by_score` stay unfiltered: per-page engagement
  # and revenue events are meaningful regardless of how the user got there.
  def self.aggregate_for!(date)
    range           = date.beginning_of_day..date.end_of_day
    all_visits      = Ahoy::Visit.where(started_at: range)
    external_visits = if INTERNAL_HOSTS.any?
                        all_visits.where(
                          "referring_domain IS NULL OR referring_domain NOT IN (?)", INTERNAL_HOSTS
                        )
                      else
                        all_visits
                      end
    all_events      = Ahoy::Event.where(time: range)
    pageviews       = all_events.where(name: "$view")
    clicks          = all_events.where(name: "SMD click")

    return if pageviews.count.zero? && all_visits.count.zero?

    find_or_create_by(date: date).update!(
      visits:              external_visits.count,
      countries:           external_visits.where.not(country: nil).group(:country).count,
      referrers:           external_visits.group("COALESCE(NULLIF(referring_domain, ''), 'direct')").count,
      paths:               pageviews.group("json_extract(properties, '$.page')").count,
      devices:             external_visits.where.not(device_type: nil).group(:device_type).count,
      browsers:            external_visits.where.not(browser: nil).group(:browser).count,
      user_agents:         external_visits.where.not(user_agent: nil).group("substr(user_agent, 1, 100)").count,
      smd_clicks_by_score: clicks.group("json_extract(properties, '$.score_id')").count
    )
  end
end
