# frozen_string_literal: true

# Re-crawls SMD scores we already have, stalest first. SmdCrawlJob discovers new
# products from SMD's sitemaps; this needs no discovery, so it walks the DB by
# last_crawled_at, which is what makes a chunked run resumable.
class SmdRefreshJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: 10.minutes, attempts: 2

  # Shared with SmdCrawlJob: each crawl holds its own rate limiter, so overlap doubles the request rate at SMD.
  limits_concurrency to: 1, key: "sheetmusicdirect.com", group: "smd_crawler", duration: 12.hours

  VALID_SCOPES = %i[all representatives].freeze

  # @param limit [Integer] how many scores to refresh this run
  # @param scope [Symbol] :all, or :representatives for the sitemap'd buy pages
  #
  # Usage:
  #   SmdRefreshJob.perform_later(limit: 500, scope: :representatives)
  #   SmdRefreshJob.perform_later(limit: 5000)
  def perform(limit: 500, scope: :all)
    require "smd_crawler/crawler"

    scope = scope.to_sym
    raise ArgumentError, "Invalid scope: #{scope}. Use #{VALID_SCOPES.join(', ')}" unless VALID_SCOPES.include?(scope)

    crawler = SmdCrawler::Crawler.new
    stats = { examined: 0, refreshed: 0, failed: 0, replaced: 0, errors: Hash.new(0), aborted: false }
    consecutive_failures = 0

    candidates(scope).limit(limit).each do |score|
      stats[:examined] += 1
      result = crawler.crawl_product(score.external_id)

      if result[:success]
        # Counted, not acted on: SMD answers a discontinued product with a 200 describing its replacement, not a 404.
        stats[:replaced] += 1 if result[:metadata][:external_id].to_s != score.external_id.to_s
        crawler.save_product(result[:metadata])
        consecutive_failures = 0
        stats[:refreshed] += 1
      else
        consecutive_failures += 1 if SmdCrawler::Crawler.blocking_error?(result[:error])
        stats[:failed] += 1
        stats[:errors][result[:error]] += 1
        Rails.logger.warn("SmdRefreshJob: #{score.external_id} failed: #{result[:error]}")
      end

      # The row we asked for, not the one save_product matched — SMD redirects
      # discontinued products, and an unstamped row blocks the queue head forever.
      score.update_column(:last_crawled_at, Time.current)

      if consecutive_failures >= SmdCrawler::Crawler::MAX_CONSECUTIVE_FAILURES
        stats[:aborted] = true
        Rails.logger.error("SmdRefreshJob: aborting after #{consecutive_failures} consecutive failures")
        Sentry.capture_message("SmdRefreshJob aborted", level: :error, extra: stats) if Sentry.initialized?
        break
      end
    end

    Rails.logger.info("SmdRefreshJob complete (scope: #{scope}): #{stats}")
    stats
  end

  private

  def candidates(scope)
    base = Score.active.smd_stalest_first.where.not(external_id: nil)
    scope == :representatives ? base.where(is_group_representative: true) : base
  end
end
