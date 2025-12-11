# config/initializers/locale.rb

# Permitted locales for the application
Rails.application.config.i18n.available_locales = [:en, :de]

# Set default locale to English
Rails.application.config.i18n.default_locale = :en

# Set fallback locale when translation is missing
Rails.application.config.i18n.fallbacks = true
