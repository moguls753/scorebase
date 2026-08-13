Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]
  config.enabled_environments = %w[production]
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]

  # GlitchTip sits behind a home uplink on dynamic IPv6 — full-rate transactions
  # widened the window in which a reconnect drops error events too.
  config.traces_sample_rate = 0.1

  config.send_default_pii = false
end
