class SitemapRefreshJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "[SitemapRefreshJob] Starting sitemap generation..."

    # Load and run config/sitemap.rb (equivalent to: rails sitemap:refresh:no_ping)
    SitemapGenerator::Interpreter.run

    Rails.logger.info "[SitemapRefreshJob] Sitemap generation completed"
  rescue => e
    Rails.logger.error "[SitemapRefreshJob] Failed: #{e.message}"
    raise
  end
end
