# == Schema Information
#
# Table name: daily_stats
#
#  id                         :integer          not null, primary key
#  browsers                   :json
#  converting_visits          :integer
#  countries                  :json
#  cross_link_visits_by_score :json
#  date                       :date
#  devices                    :json
#  paths                      :json
#  referrers                  :json
#  returning_rates            :json
#  smd_clicks_by_score        :json
#  user_agents                :json
#  visits                     :integer          default(0)
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
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

  RETURNING_WINDOWS = { "7d" => 7, "30d" => 30, "90d" => 90, "180d" => 180 }.freeze

  def total_smd_clicks
    (smd_clicks_by_score || {}).values.sum
  end

  def total_cross_link_visits
    (cross_link_visits_by_score || {}).values.sum
  end

  # Nil for rows aggregated before `converting_visits` existed: the dashboard
  # renders those as "—" rather than a misleading 0%.
  def smd_conversion_rate
    return nil if visits.to_i.zero? || converting_visits.nil?
    (converting_visits * 100.0 / visits).round(1)
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
  # `converting_visits` must stay filtered to match the `visits` denominator —
  # ~89% of click events happen on internal-referrer visits, so dividing the
  # unfiltered click count by `visits` yields rates well over 100%.
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
    cross_links     = all_events.where(name: "Cross-link visit")
    external_clicks = clicks.where(visit_id: external_visits.select(:id))

    return if pageviews.count.zero? && all_visits.count.zero?

    find_or_create_by(date: date).update!(
      visits:              external_visits.count,
      converting_visits:   external_clicks.distinct.count(:visit_id),
      countries:           external_visits.where.not(country: nil).group(:country).count,
      referrers:           external_visits.group("COALESCE(NULLIF(referring_domain, ''), 'direct')").count,
      paths:               pageviews.group("json_extract(properties, '$.page')").count,
      devices:             external_visits.where.not(device_type: nil).group(:device_type).count,
      browsers:            external_visits.where.not(browser: nil).group(:browser).count,
      user_agents:         external_visits.where.not(user_agent: nil).group("substr(user_agent, 1, 100)").count,
      smd_clicks_by_score: clicks.group("json_extract(properties, '$.score_id')").count,
      cross_link_visits_by_score: cross_links.group("json_extract(properties, '$.score_id')").count,
      returning_rates:     returning_rates_for(date)
    )
  end

  def self.returning_rates_for(date)
    today_hashes = Ahoy::Visit
                     .where(started_at: date.all_day)
                     .where.not(visitor_hash: nil)
                     .distinct.pluck(:visitor_hash)
    return RETURNING_WINDOWS.transform_values { 0.0 } if today_hashes.empty?

    today_set = today_hashes.to_set
    total     = today_set.size

    RETURNING_WINDOWS.transform_values do |window_days|
      prior_range = (date - window_days.days).beginning_of_day...date.beginning_of_day
      prior_pairs = Ahoy::Visit.where(started_at: prior_range)
                               .pluck(:visitor_hash, :visitor_hash_next)

      prior_set = Set.new
      prior_pairs.each do |h, hn|
        prior_set << h  if h.present?
        prior_set << hn if hn.present?
      end

      (today_set & prior_set).size.to_f / total
    end
  end
end
