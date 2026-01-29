# frozen_string_literal: true

class SmdCrawlJob < ApplicationJob
  queue_as :default

  # Long-running job, limit retries
  retry_on StandardError, wait: 10.minutes, attempts: 2

  # Crawl SMD products from Hal Leonard catalog
  #
  # @param limit [Integer, nil] Max products to crawl (nil = all)
  # @param skip_existing [Boolean] Skip already imported products
  # @param catalog [String] Which catalog: "hl", "ame", or "other"
  #
  # Usage:
  #   SmdCrawlJob.perform_later(limit: 100)  # Test with 100 products
  #   SmdCrawlJob.perform_later               # Full crawl
  #
  def perform(limit: nil, skip_existing: true, catalog: "hl")
    require "smd_crawler/crawler"

    index_url = sitemap_index_url(catalog)
    Rails.logger.info "Starting SMD crawl (catalog: #{catalog}, limit: #{limit || 'unlimited'}, skip_existing: #{skip_existing})"

    crawler = SmdCrawler::Crawler.new
    stats = crawler.crawl_index(
      index_url,
      product_limit: limit,
      skip_existing: skip_existing
    )

    Rails.logger.info "SMD crawl complete: #{stats}"
    stats
  end

  private

  def sitemap_index_url(catalog)
    base = "https://www.sheetmusicdirect.com/sitemaps"
    case catalog
    when "hl"    then "#{base}/sitemap-index-prod-hl.xml"
    when "ame"   then "#{base}/sitemap-index-prod-ame.xml"
    when "other" then "#{base}/sitemap-index-prod-other.xml"
    else raise ArgumentError, "Unknown catalog: #{catalog}. Use 'hl', 'ame', or 'other'"
    end
  end
end
