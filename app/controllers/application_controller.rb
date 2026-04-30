class ApplicationController < ActionController::Base
  include Ahoy::Controller

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Set locale from URL path or browser preference
  around_action :switch_locale

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

  # Used by non-Ahoy callers (e.g. ScoresController view-counter increment).
  # Ahoy itself does its own bot detection inside Ahoy::Tracker.
  def bot?
    ua = request.user_agent
    return true if ua.blank? || ua.length < 20
    DeviceDetector.new(ua).bot?
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
