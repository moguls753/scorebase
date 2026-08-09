# == Schema Information
#
# Table name: daily_stats
#
#  id                      :integer          not null, primary key
#  countries               :json
#  date                    :date
#  devices                 :json
#  human_converting_visits :integer
#  human_visits            :integer
#  paths                   :json
#  referrers               :json
#  smd_clicks_by_score     :json
#  smd_page_visits         :integer
#  visits                  :integer          default(0)
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#
# Indexes
#
#  index_daily_stats_on_date  (date) UNIQUE
#
class DailyStat < ApplicationRecord
  # ENV-configurable so dev/staging/prod can each declare their own on-site hosts.
  INTERNAL_HOSTS = ENV.fetch("INTERNAL_ANALYTICS_HOSTS", "scorebase.org")
                      .split(",").map(&:strip).reject(&:empty?).freeze

  REFERRER_CAPTURE_STARTED_ON = Date.new(2026, 7, 16)

  scope :in_window, ->(days) { where(date: (days - 1).days.ago.to_date..Date.current) }
  scope :measured,  -> { where.not(human_visits: nil) }

  def total_smd_clicks
    (smd_clicks_by_score || {}).values.sum
  end

  # "google." prefix keeps the search TLDs (google.com, google.de, google.co.uk)
  # and drops mail.google.com and the Android app's com.google.* referrers.
  def google_visits
    return nil if human_visits.nil?
    (referrers || {}).sum { |host, count| host.start_with?("google.") ? count : 0 }
  end

  def self.summary
    # Unmeasured rows carry visits but no human_visits — including them divides a short numerator by a full denominator.
    rows   = measured.to_a
    raw    = rows.sum { |r| r.visits.to_i }
    humans = rows.sum { |r| r.human_visits.to_i }

    # smd_page_visits arrived in a later migration, so a measured row can still lack it.
    # Every funnel figure sums this narrower set, or the rate divides a full numerator by a partial denominator.
    funnel     = rows.select(&:smd_page_visits)
    reach_base = funnel.sum { |r| r.human_visits.to_i }
    smd_seen   = funnel.sum(&:smd_page_visits)
    conv       = funnel.sum { |r| r.human_converting_visits.to_i }

    {
      days:            rows.size,
      funnel_days:     funnel.size,
      visits:          raw,
      human_visits:    humans,
      google_visits:   rows.sum { |r| r.google_visits.to_i },
      smd_page_visits: smd_seen,
      avg_human:       rows.empty? ? 0 : (humans.to_f / rows.size).round,
      human_share:     raw.zero? ? nil : (humans * 100.0 / raw).round(1),
      smd_reach:       reach_base.zero? ? nil : (smd_seen * 100.0 / reach_base).round(1),
      smd_clicks:      funnel.sum(&:total_smd_clicks),
      converting:      conv,
      conversion_rate: smd_seen.zero? ? nil : (conv * 100.0 / smd_seen).round(1)
    }
  end

  # Idempotent; skipped on days with no Ahoy data so pre-cutover rows aren't clobbered with zeros.
  def self.aggregate_for!(date)
    range           = date.beginning_of_day..date.end_of_day
    all_visits      = Ahoy::Visit.where(started_at: range)
    external_visits = if INTERNAL_HOSTS.any?
      all_visits.where("referring_domain IS NULL OR referring_domain NOT IN (?)", INTERNAL_HOSTS)
    else
      all_visits
    end
    pageviews = Ahoy::Event.where(time: range, name: "$view")
    clicks    = Ahoy::Event.where(time: range, name: "SMD click")

    return if pageviews.count.zero? && all_visits.count.zero?

    attrs = { visits: external_visits.count }

    if date >= REFERRER_CAPTURE_STARTED_ON
      # Referrer, not pageview count: crawlers walking the catalogue also rack up pageviews, and the
      # multi-view-no-referrer cohort measured 7.6% mobile against 27% for referred traffic.
      humans       = external_visits.where(id: pageviews.select(:visit_id)).where.not(referring_domain: nil)
      human_views  = pageviews.where(visit_id: humans.select(:id))
      human_clicks = clicks.where(visit_id: humans.select(:id))

      attrs.merge!(
        human_visits:            humans.count,
        smd_page_visits:         human_views.on_smd_score_page.distinct.count(:visit_id),
        human_converting_visits: human_clicks.distinct.count(:visit_id),
        countries:               humans.where.not(country: nil).group(:country).count,
        referrers:               humans.group("COALESCE(NULLIF(referring_domain, ''), 'direct')").count,
        devices:                 humans.where.not(device_type: nil).group(:device_type).count,
        paths:                   human_views.group("json_extract(properties, '$.page')").distinct.count(:visit_id),
        smd_clicks_by_score:     human_clicks.group("json_extract(properties, '$.score_id')").count
      )
    end

    find_or_create_by(date: date).update!(attrs)
  end
end
