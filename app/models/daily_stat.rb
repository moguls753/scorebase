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
  def self.track_visit!(user_agent: nil, country: nil, referer: nil, path: nil, device: nil)
    daily_stat = find_or_create_by(date: Date.current)
    daily_stat.increment!(:visits)

    # Use a mutex to prevent race conditions on JSON updates
    # For higher traffic, consider moving to Redis or a separate analytics table
    daily_stat.with_lock do
      daily_stat.reload

      if user_agent.present?
        # Track user agents (truncated)
        agents = daily_stat.user_agents || {}
        key = user_agent.truncate(100, omission: "")
        agents[key] = (agents[key] || 0) + 1
        daily_stat.user_agents = agents

        # Parse browser from user agent
        browser = parse_browser(user_agent)
        browsers = daily_stat.browsers || {}
        browsers[browser] = (browsers[browser] || 0) + 1
        daily_stat.browsers = browsers
      end

      if country.present?
        countries = daily_stat.countries || {}
        countries[country.upcase] = (countries[country.upcase] || 0) + 1
        daily_stat.countries = countries
      end

      # Track referrer (including "direct" for missing)
      referrers = daily_stat.referrers || {}
      domain = extract_referrer_domain(referer)
      referrers[domain] = (referrers[domain] || 0) + 1
      daily_stat.referrers = referrers

      if path.present?
        paths = daily_stat.paths || {}
        # Only track route patterns, not individual IDs (to prevent explosion)
        normalized = normalize_path(path)
        paths[normalized] = (paths[normalized] || 0) + 1
        daily_stat.paths = paths
      end

      if device.present?
        devices = daily_stat.devices || {}
        devices[device.downcase] = (devices[device.downcase] || 0) + 1
        daily_stat.devices = devices
      end

      daily_stat.save!
    end
  end

  def self.parse_browser(user_agent)
    case user_agent
    when /Edg\// then "Edge"
    when /OPR|Opera/ then "Opera"
    when /Chrome/ then "Chrome"
    when /Safari/ then "Safari"
    when /Firefox/ then "Firefox"
    else "Other"
    end
  end

  def self.extract_referrer_domain(referer)
    return "direct" if referer.blank?
    URI.parse(referer).host&.gsub(/^www\./, "") || "direct"
  rescue URI::InvalidURIError
    "invalid"
  end

  def self.normalize_path(path)
    # Replace numeric IDs with :id to prevent path explosion
    # /scores/12345 → /scores/:id
    # /de/scores/12345 → /de/scores/:id
    path.split("?").first
        .gsub(%r{/\d+}, "/:id")
        .truncate(100, omission: "")
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
