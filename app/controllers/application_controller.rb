class ApplicationController < ActionController::Base
  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Set locale from URL path or browser preference
  around_action :switch_locale
  after_action :track_visit

  private

  def switch_locale(&action)
    locale = extract_locale
    I18n.with_locale(locale, &action)
  end

  def extract_locale
    # Priority: URL path param > browser Accept-Language header > default
    parsed_locale = params[:locale] || extract_locale_from_accept_language_header

    # Return only if it's a valid locale, otherwise fall back to default
    I18n.available_locales.map(&:to_s).include?(parsed_locale) ? parsed_locale : I18n.default_locale
  end

  def extract_locale_from_accept_language_header
    return nil unless request.env["HTTP_ACCEPT_LANGUAGE"]

    # Parse Accept-Language header and find first matching locale
    accepted_languages = request.env["HTTP_ACCEPT_LANGUAGE"]
      .split(",")
      .map { |lang| lang.split(";").first.strip.split("-").first.downcase }

    accepted_languages.find { |lang| I18n.available_locales.map(&:to_s).include?(lang) }
  end

  def default_url_options
    { locale: I18n.locale == I18n.default_locale ? nil : I18n.locale }
  end

  def track_visit
    return if bot? || prefetch?
    return if request.path.start_with?("/admin", "/jobs")
    DailyStat.track_visit!(
      user_agent: request.user_agent,
      country: request.headers["CF-IPCountry"],
      referer: request.referer,
      path: request.path,
      device: request.headers["CF-Device-Type"] || device_type_from_user_agent
    )
  end

  def device_type_from_user_agent
    ua = request.user_agent.to_s
    case ua
    when /Mobile|Android.*Mobile|iPhone|iPod|BlackBerry|IEMobile|Opera Mini/i
      "mobile"
    when /iPad|Android(?!.*Mobile)|Tablet/i
      "tablet"
    else
      "desktop"
    end
  end

  def bot?
    # Primary detection via crawler_detect gem (checks 11 HTTP headers, 1000s of bots)
    return true if request.is_crawler?

    # Fallback checks for edge cases the gem might miss
    user_agent = request.user_agent.to_s

    # Empty or suspiciously short user agents
    return true if user_agent.blank? || user_agent.length < 20

    # Mozilla/5.0 without device info parentheses = spoofed
    return true if user_agent.match?(/^Mozilla\/5\.0 [^(]/)

    # DevTools mobile emulation signatures (ancient devices used for scraping)
    return true if user_agent.match?(/
      SM-G900P|                          # Galaxy S5 (2014)
      Nexus\ 5\ Build\/MRA58N|           # Nexus 5 (2015)
      Pixel\ 2\ Build\/OPD3|             # Pixel 2 DevTools emulation
      iPhone\ OS\ 1[0-3]_|               # iOS 10-13 (2016-2019)
      Android\ [45]\.0                   # Android 4.x-5.x (2013-2015)
    /x)

    # Old browser versions (bots using outdated but valid-looking signatures)
    if (match = user_agent.match(/Chrome\/(\d+)\./))
      return true if match[1].to_i < 130  # Chrome 130 = Oct 2024
    end
    if (match = user_agent.match(/Firefox\/(\d+)\./))
      version = match[1].to_i
      # Block < 115 (ancient) OR 116-127 (non-ESR gap between Tor's 115 and current ESR 128)
      return true if version < 115 || (version > 115 && version < 128)
    end

    false
  end

  def prefetch?
    request.headers["Sec-Purpose"] == "prefetch" ||
      request.headers["Purpose"] == "prefetch"
  end

  # Protect production site during testing phase
  # Remove this once ready to launch publicly
  # Set password via: rails credentials:edit
  # Add: basic_auth: { user: "admin", password: "your_password" }
  # http_basic_authenticate_with(
  #   name: Rails.application.credentials.dig(:basic_auth, :user) || "admin",
  #   password: Rails.application.credentials.dig(:basic_auth, :password),
  #   if: -> { Rails.env.production? && Rails.application.credentials.dig(:basic_auth, :password).present? }
  # )
end
