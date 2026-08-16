# frozen_string_literal: true

require "net/http"

# Harvests every product id from Stretta's sitemap (docs/stretta-import-plan.md §2).
#
# The Storefront `products` connection is capped at 25,000 elements under every
# sort key, so the sitemap is the only complete id source. It is not a perfect
# one: 8.2% of its ids are dead, and products exist that it omits. Never delete a
# score on its evidence alone — check the API first.
module Stretta
  class SitemapHarvester
    INDEX_URL = "https://www.stretta-music.de/sitemap.xml"

    # Measured 2026-08-15: the sitemap host answers Ruby's Net::HTTP with 403 and
    # `cf-mitigated: challenge` under every header set tried, while curl with the
    # same headers gets the XML — the gate is on the TLS/HTTP fingerprint, so it
    # goes through the bypass accessory like CPDL. The GraphQL API is not gated.
    HEADERS = {
      "User-Agent" => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 " \
                      "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36",
      "Accept" => "application/xml,text/xml,*/*;q=0.8",
      "Accept-Language" => "de-DE,de;q=0.9,en;q=0.8"
    }.freeze

    PRODUCT_SITEMAP = %r{/sitemap/articles/\d+\.xml\z}
    PRODUCT_ID = /-nr-(\d+)\.html/
    LOC = %r{<loc>([^<]+)</loc>}

    class IncompleteHarvest < StandardError; end

    def initialize(logger: Rails.logger, http: CloudflareBypassClient.new)
      @logger = logger
      @http = http
    end

    # Yields ids as they are parsed — 1.87M of them must never be one array in a
    # 1 GB container, and neither must a single child sitemap's DOM.
    def each_handle
      return enum_for(:each_handle) unless block_given?

      urls = child_sitemaps
      raise IncompleteHarvest, "sitemap index listed no product sitemaps" if urls.empty?

      failed = 0
      urls.each_with_index do |url, index|
        begin
          scan(url) { |handle| yield handle }
        rescue StandardError => e
          failed += 1
          @logger.warn "[Stretta::SitemapHarvester] #{url} failed: #{e.class}"
        end
        @logger.info "[Stretta::SitemapHarvester] #{index + 1}/#{urls.size}" if ((index + 1) % 100).zero?
      end

      # Partial coverage read as truth would delete everything the missing files
      # held, so it is an abort rather than a smaller result.
      raise IncompleteHarvest, "#{failed} of #{urls.size} child sitemaps failed" if failed.positive?
    end

    def child_sitemaps
      body(INDEX_URL).scan(LOC).flatten.grep(PRODUCT_SITEMAP)
    end

    private

    def scan(url)
      body(url).scan(LOC) { |(loc)| loc[PRODUCT_ID, 1]&.then { |id| yield id } }
    end

    def body(url)
      response = @http.get(url)
      raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      content = response.body
      # Cloudflare's challenge is served as a 200 carrying HTML, so the status
      # code alone never tells you the fetch failed.
      raise "not XML (Cloudflare challenge?)" unless content.to_s.lstrip.start_with?("<?xml", "<sitemapindex", "<urlset")

      content
    end
  end
end
