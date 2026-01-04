require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Scorebase
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Use RSpec instead of minitest for generators
    config.generators do |g|
      g.test_framework :rspec
    end

    # PDMX dataset path (external, not in repo)
    # Dev: ~/data/pdmx (default), Prod: /opt/pdmx (via PDMX_DATA_PATH)
    config.x.pdmx_path = Pathname.new(ENV.fetch("PDMX_DATA_PATH", File.expand_path("~/data/pdmx")))

    # OpenScore corpus paths (MXL source files)
    # Dev: ~/data/openscore-*, Prod: /opt/openscore-* (via ENV)
    config.x.openscore_path = Pathname.new(ENV.fetch("OPENSCORE_LIEDER_PATH", File.expand_path("~/data/openscore-lieder")))
    config.x.openscore_quartets_path = Pathname.new(ENV.fetch("OPENSCORE_QUARTETS_PATH", File.expand_path("~/data/openscore-quartets")))

    # OpenScore PDFs path (generated from MXL via MuseScore)
    # Structure: openscore-pdfs/{lieder,quartets}/{external_id}.pdf
    config.x.openscore_pdfs_path = Pathname.new(ENV.fetch("OPENSCORE_PDFS_PATH", "/opt/openscore-pdfs"))
  end
end
