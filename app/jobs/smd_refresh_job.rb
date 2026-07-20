# frozen_string_literal: true

# Re-crawls SMD scores we already have, stalest first.
#
# Distinct from SmdCrawlJob, which walks SMD's sitemaps to *discover* products.
# Refreshing needs no discovery — every external_id is already in the database —
# so this iterates the DB directly, ordered by last_crawled_at. That ordering is
# what makes a chunked run resumable: each run picks up where the last stopped.
class SmdRefreshJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: 10.minutes, attempts: 2

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
    stats = { examined: 0, refreshed: 0, failed: 0 }

    candidates(scope).limit(limit).each do |score|
      stats[:examined] += 1
      result = crawler.crawl_product(score.external_id)

      if result[:success]
        crawler.save_product(result[:metadata])
        stats[:refreshed] += 1
      else
        # Stamp failures too, otherwise a permanently broken row blocks the
        # queue head forever and the run never advances past it.
        score.update_column(:last_crawled_at, Time.current)
        stats[:failed] += 1
        Rails.logger.warn("SmdRefreshJob: #{score.external_id} failed: #{result[:error]}")
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
