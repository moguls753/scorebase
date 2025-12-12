class SitemapRefreshJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "[SitemapRefreshJob] Starting sitemap generation..."

    SitemapGenerator::Sitemap.create

    Rails.logger.info "[SitemapRefreshJob] Sitemap generation completed"
  rescue => e
    Rails.logger.error "[SitemapRefreshJob] Failed: #{e.message}"
    raise
  end
end
