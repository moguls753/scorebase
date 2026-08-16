# == Schema Information
#
# Table name: daily_stats
#
#  id                        :integer          not null, primary key
#  countries                 :json
#  date                      :date
#  devices                   :json
#  human_converting_visits   :integer
#  human_visits              :integer
#  partner_clicks_by_score   :json
#  partner_converting_visits :json
#  partner_page_visits       :json
#  paths                     :json
#  referrers                 :json
#  smd_clicks_by_score       :json
#  smd_page_visits           :integer
#  visits                    :integer          default(0)
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
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

  # Legacy rows carry the SMD-only columns; rows written after the partner split
  # carry the JSON. Reading through these two keeps the historical series intact.
  def page_visits(source)
    partner_page_visits&.dig(source) || (source == "smd" ? smd_page_visits : nil)
  end

  def clicks_by_score(source)
    partner_clicks_by_score&.dig(source) || (source == "smd" ? smd_clicks_by_score : nil) || {}
  end

  def converting_visits(source)
    partner_converting_visits&.dig(source) || (source == "smd" ? human_converting_visits : nil)
  end

  def total_clicks(source)
    clicks_by_score(source).values.sum
  end

  def measured_partners
    partner_page_visits&.keys.presence || (smd_page_visits ? %w[smd] : [])
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

    partners = Score::COMMERCIAL_SOURCES.index_with { |source| partner_funnel(rows, source) }
    combined = partners.values.select { |f| f[:days].positive? }

    {
      days:          rows.size,
      visits:        raw,
      human_visits:  humans,
      google_visits: rows.sum { |r| r.google_visits.to_i },
      avg_human:     rows.empty? ? 0 : (humans.to_f / rows.size).round,
      human_share:   raw.zero? ? nil : (humans * 100.0 / raw).round(1),
      partners:      partners,
      # Kept flat for the dashboard headline; SMD alone until Stretta has history.
      funnel_days:     combined.map { |f| f[:days] }.max.to_i,
      smd_page_visits: combined.sum { |f| f[:page_visits] },
      smd_reach:       partners["smd"][:reach],
      smd_clicks:      combined.sum { |f| f[:clicks] },
      converting:      combined.sum { |f| f[:converting] },
      conversion_rate: partners["smd"][:conversion_rate]
    }
  end

  # The funnel columns arrived in a later migration, so a measured row can still
  # lack them. Every figure sums that narrower set, or a rate divides a full
  # numerator by a partial denominator.
  def self.partner_funnel(rows, source)
    funnel = rows.select { |r| r.page_visits(source) }
    seen   = funnel.sum { |r| r.page_visits(source).to_i }
    conv   = funnel.sum { |r| r.converting_visits(source).to_i }
    base   = funnel.sum { |r| r.human_visits.to_i }

    {
      days:            funnel.size,
      page_visits:     seen,
      clicks:          funnel.sum { |r| r.total_clicks(source) },
      converting:      conv,
      reach:           base.zero? ? nil : (seen * 100.0 / base).round(1),
      conversion_rate: seen.zero? ? nil : (conv * 100.0 / seen).round(1)
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

    return if pageviews.count.zero? && all_visits.count.zero?

    attrs = { visits: external_visits.count }

    if date >= REFERRER_CAPTURE_STARTED_ON
      # Referrer, not pageview count: crawlers walking the catalogue also rack up pageviews, and the
      # multi-view-no-referrer cohort measured 7.6% mobile against 27% for referred traffic.
      humans      = external_visits.where(id: pageviews.select(:visit_id)).where.not(referring_domain: nil)
      human_views = pageviews.where(visit_id: humans.select(:id))

      funnel = Ahoy::Event::CLICK_EVENTS.to_h do |source, event_name|
        partner_clicks = Ahoy::Event.where(time: range, name: event_name, visit_id: humans.select(:id))
        [ source, {
          page_visits: human_views.on_partner_score_page(source).distinct.count(:visit_id),
          converting:  partner_clicks.distinct.count(:visit_id),
          by_score:    partner_clicks.group("json_extract(properties, '$.score_id')").count
        } ]
      end

      attrs.merge!(
        human_visits:              humans.count,
        countries:                 humans.where.not(country: nil).group(:country).count,
        referrers:                 humans.group("COALESCE(NULLIF(referring_domain, ''), 'direct')").count,
        devices:                   humans.where.not(device_type: nil).group(:device_type).count,
        paths:                     human_views.group("json_extract(properties, '$.page')").distinct.count(:visit_id),
        partner_page_visits:       funnel.transform_values { |f| f[:page_visits] },
        partner_converting_visits: funnel.transform_values { |f| f[:converting] },
        partner_clicks_by_score:   funnel.transform_values { |f| f[:by_score] },
        # The three SMD columns stay written so the pre-split series keeps one shape.
        smd_page_visits:           funnel.dig("smd", :page_visits),
        human_converting_visits:   funnel.dig("smd", :converting),
        smd_clicks_by_score:       funnel.dig("smd", :by_score)
      )
    end

    find_or_create_by(date: date).update!(attrs)
  end
end
