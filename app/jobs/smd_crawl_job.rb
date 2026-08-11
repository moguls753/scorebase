# frozen_string_literal: true

class SmdCrawlJob < ApplicationJob
  queue_as :default

  # Long-running job, limit retries
  retry_on StandardError, wait: 10.minutes, attempts: 2

  # Shared with SmdRefreshJob: each crawl holds its own rate limiter, so overlap doubles the request rate at SMD.
  limits_concurrency to: 1, key: "sheetmusicdirect.com", group: "smd_crawler", duration: 12.hours

  VALID_MODES = %i[import all].freeze

  # Discovers SMD products by walking SMD's own sitemaps.
  #
  # Refreshing scores we already have is SmdRefreshJob's job — it iterates the
  # database instead. Here the skip is the cursor: yesterday's saves are today's
  # skips, so a limited run advances even though the walk restarts each time.
  # A product SMD answers under a different mpn never becomes a skip, so
  # stats[:replaced] nearing the limit means the walk needs a persisted cursor.
  #
  # @param limit [Integer, nil] Max products to process (nil = all)
  # @param mode [Symbol] :import (new only) or :all (re-crawl everything listed)
  # @param catalog [String] Which catalog: "hl", "ame", or "other"
  #
  # Usage:
  #   SmdCrawlJob.perform_later(limit: 100)   # Import 100 new
  #   SmdCrawlJob.perform_later(mode: :all)   # Full crawl
  #
  def perform(limit: nil, mode: :import, catalog: "hl")
    require "smd_crawler/crawler"

    mode = mode.to_sym
    raise ArgumentError, "Invalid mode: #{mode}. Use #{VALID_MODES.join(', ')}" unless VALID_MODES.include?(mode)

    index_url = sitemap_index_url(catalog)
    Rails.logger.info "Starting SMD crawl (catalog: #{catalog}, mode: #{mode}, limit: #{limit || 'unlimited'})"

    crawler = SmdCrawler::Crawler.new
    stats = crawler.crawl_index(
      index_url,
      product_limit: limit,
      mode: mode
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
