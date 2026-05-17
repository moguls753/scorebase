# Ahoy is wired through DailyStat: hourly AggregateDailyStatsJob rolls
# Ahoy data into DailyStat rows that the Avo dashboard reads. Ahoy data
# itself is pruned after 30 days; DailyStat is the long-term aggregate.

class Ahoy::Store < Ahoy::DatabaseStore
  # device_detector returns ~13 device categories; the dashboard only knows
  # desktop / mobile / tablet. Bucket on the way in so historical rows and
  # new rows share the same key set.
  DEVICE_BUCKETS = Hash.new("desktop").merge!(
    "desktop"        => "desktop",
    "smartphone"     => "mobile",
    "phablet"        => "mobile",
    "feature phone"  => "mobile",
    "feature_phone"  => "mobile",
    "tablet"         => "tablet"
  ).freeze

  def track_visit(data)
    if (req = request)
      cf_country = req.headers["CF-IPCountry"]
      data[:country] = cf_country.upcase if cf_country.present?

      cf_device = req.headers["CF-Device-Type"]
      data[:device_type] = cf_device if cf_device.present?

      ip = req.headers["CF-Connecting-IP"].presence || req.remote_ip
      ua = req.user_agent.to_s
      today = Date.current
      data[:visitor_hash]      = VisitorHash.from(ip: ip, user_agent: ua, date: today)
      data[:visitor_hash_next] = VisitorHash.from_next(ip: ip, user_agent: ua, date: today)
    end

    # Privacy: don't store IPs at rest. mask_ips below is the belt; this is the braces.
    data[:ip] = nil

    data[:device_type] = bucket_device(data[:device_type])

    # Normalise www-prefixed referring domains so the dashboard doesn't split
    # `www.google.com` and `google.com` into separate rows.
    if data[:referring_domain].is_a?(String) && data[:referring_domain].start_with?("www.")
      data[:referring_domain] = data[:referring_domain].sub(/\Awww\./, "")
    end

    super
  end

  private

  def bucket_device(value)
    return nil if value.blank?
    DEVICE_BUCKETS[value.to_s.downcase]
  end
end

# Pageviews are tracked from JavaScript via /ahoy/events to filter scrapers
# that don't run JS. Server-side ahoy.track (e.g. SMD click during redirect)
# still works: :when_needed creates the visit lazily for events that need one.
Ahoy.api = true
Ahoy.server_side_visits = :when_needed

# No IP-based geocoding; we set country from Cloudflare's CF-IPCountry header in the Store.
Ahoy.geocode = false

# No cookies. Every request is its own anonymous visit. Keeps the privacy
# stance ("no cookies beyond the Rails session") accurate. ahoy.js is also
# configured with cookies: false on the JS side (see app/javascript).
Ahoy.cookies = :none

# Anonymise IPs at the framework level. The Store override also sets ip=nil,
# so this is defense in depth in case a future code path bypasses the Store.
Ahoy.mask_ips = true

# Skip tracking for admin pages, the Solid Queue dashboard, prefetch hits, and
# the score-file download endpoints (those are content access, not user
# behavior, and dominate the dashboard with bulk-harvest noise).
# Bot detection (device_detector) is handled separately inside Ahoy::Tracker.
Ahoy.exclude_method = lambda do |_controller, request|
  request.path.start_with?("/admin", "/jobs") ||
    request.path.match?(%r{\A/(?:de/)?scores/\d+/file(?:/|\z)}) ||
    request.headers["Sec-Purpose"] == "prefetch" ||
    request.headers["Purpose"] == "prefetch"
end
