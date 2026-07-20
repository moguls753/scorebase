# Ahoy is wired through DailyStat: hourly AggregateDailyStatsJob rolls
# Ahoy data into DailyStat rows that the Avo dashboard reads. Ahoy data
# itself is pruned after AggregateDailyStatsJob::RETENTION_DAYS; DailyStat
# is the long-term aggregate.

class Ahoy::Store < Ahoy::DatabaseStore
  # device_detector returns ~13 device categories; the dashboard only knows
  # desktop / mobile / tablet. Bucket on the way in so historical rows and
  # new rows share the same key set.
  # Two vocabularies land here: Cloudflare's CF-Device-Type (mobile/tablet/desktop)
  # and device_detector's (smartphone/phablet/…). Missing "mobile" silently bucketed
  # every phone as desktop for months — the default hid it, so it is "unknown" now.
  DEVICE_BUCKETS = Hash.new("unknown").merge!(
    "desktop"        => "desktop",
    "mobile"         => "mobile",
    "smartphone"     => "mobile",
    "phablet"        => "mobile",
    "feature phone"  => "mobile",
    "feature_phone"  => "mobile",
    "tablet"         => "tablet"
  ).freeze

  HOSTNAME = /\A[a-z0-9]([a-z0-9\-.]{0,251}[a-z0-9])?\z/i

  # ahoy.js runs with cookies:false, which short-circuits its createVisit() — the
  # visits endpoint is never hit, and in api mode Ahoy::VisitProperties reads
  # params["referrer"] instead of request.referer. So the browser sends the
  # referrer's hostname (never the URL) as an event property and we lift it onto
  # the visit here, then drop it so traffic source lives in exactly one column.
  def track_event(data)
    props = data[:properties]
    if props.is_a?(Hash)
      @js_referring_domain = props.delete("referring_domain") || props.delete(:referring_domain)
    end

    super
  end

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

    data[:referring_domain] = normalize_domain(@js_referring_domain || data[:referring_domain])

    # Privacy: a full Referer can carry search queries, private URLs and tokens.
    # The hostname above is the only traffic-source data we keep.
    data[:referrer] = nil

    super
  end

  private

  def bucket_device(value)
    return nil if value.blank?
    DEVICE_BUCKETS[value.to_s.downcase]
  end

  # Also normalises www-prefixed domains so the dashboard doesn't split
  # `www.google.com` and `google.com` into separate rows.
  def normalize_domain(value)
    return nil unless value.is_a?(String)

    host = value.strip.downcase
    return nil unless host.match?(HOSTNAME)

    host.delete_prefix("www.").presence
  end
end

# Pageviews are tracked from JavaScript via /ahoy/events to filter scrapers
# that don't run JS. Server-side ahoy.track (e.g. SMD click during redirect)
# still works: :when_needed creates the visit lazily for events that need one.
Ahoy.api = true
Ahoy.server_side_visits = :when_needed

# No IP-based geocoding; we set country from Cloudflare's CF-IPCountry header in the Store.
Ahoy.geocode = false

# No cookies, no device storage — this is what lets us run without a consent
# banner. ahoy.js is also configured with cookies: false (see app/javascript).
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
