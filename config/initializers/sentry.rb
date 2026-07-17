Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]
  config.enabled_environments = %w[production]
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]

  # Performance monitoring: fraction of requests/jobs sent as transactions.
  # Low-traffic hobby app on a self-hosted (unlimited) GlitchTip — capture all.
  # Lower this if event volume ever grows.
  config.traces_sample_rate = 1.0

  config.send_default_pii = false
end
