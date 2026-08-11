# frozen_string_literal: true

require_relative "sitemap_parser"
require_relative "page_fetcher"
require_relative "metadata_extractor"

module SmdCrawler
  class Crawler
    PRODUCT_URL_TEMPLATE = "https://www.sheetmusicdirect.com/se/ID_No/%s/Product.aspx"
    MAX_CONSECUTIVE_FAILURES = 25
    # Measured 2026-08-11: 0 of 120 sampled missing ids 404ed or answered under another mpn, so a
    # healthy run spends ~1.0 fetches per save. 2 leaves headroom without letting a bad run run away.
    MAX_FETCHES_PER_SAVE = 2
    # Denylist, not an allowlist: PageFetcher emits a catch-all "http_#{status}", and an unrecognised
    # error must count towards the abort rather than let a blocked run walk the whole sitemap.
    NON_BLOCKING_ERRORS = %w[not_found].freeze
    # Everything else is upstream of our enrichment — rewriting composer here
    # reverts NormalizeComposersJob and drops scores off their composer hub.
    REFRESHABLE = %i[
      title price_usd original_price_usd rating review_count page_count
      is_interactive last_crawled_at
    ].freeze

    def self.blocking_error?(error)
      !NON_BLOCKING_ERRORS.include?(error)
    end

    def initialize(fetcher: nil, parser: nil, extractor: nil)
      @fetcher = fetcher || PageFetcher.new
      @parser = parser || SitemapParser.new
      @extractor = extractor || MetadataExtractor.new
    end

    # Crawl a single product by ID
    def crawl_product(product_id)
      url = PRODUCT_URL_TEMPLATE % product_id
      result = @fetcher.fetch(url)

      return { success: false, error: result[:error] } unless result[:success]

      metadata = @extractor.extract(result[:body])

      # Cloudflare's challenge interstitial is a 200 with no ld+json.
      return { success: false, error: "unparseable" } unless product?(metadata)

      { success: true, metadata: metadata }
    end

    def save_product(metadata)
      score = Score.find_or_initialize_by(
        external_id: metadata[:external_id],
        source: "smd"
      )

      attributes = {
        title: metadata[:title],
        composer: metadata[:composer],
        artist: metadata[:artist],
        contributors: metadata[:contributors],
        instruments: metadata[:instruments],
        main_instrument: metadata[:main_instrument],
        tags: metadata[:tags],
        smd_category: metadata[:smd_category],
        arrangement_category: metadata[:arrangement_category],
        pedagogical_grade: map_difficulty_to_grade(metadata[:difficulty]),
        brand: metadata[:brand],
        is_arrangeme: metadata[:is_arrangeme],
        price_usd: metadata[:price_usd],
        original_price_usd: metadata[:original_price_usd],
        rating: metadata[:rating],
        review_count: metadata[:review_count],
        page_count: metadata[:page_count],
        pitch_range: metadata[:pitch_range],
        is_interactive: metadata[:is_interactive],
        thumbnail_url: metadata[:thumbnail_url],
        preview_image_url: metadata[:preview_image_url],
        period: smd_period(metadata[:tags]),
        period_status: "normalized",
        last_crawled_at: Time.current
      }

      # .compact: a partial parse must not null out a good price.
      attributes = attributes.slice(*REFRESHABLE).compact if score.persisted?

      score.assign_attributes(attributes)

      score.save!
      score
    end

    # Crawl all products listed in one of SMD's sitemap XML documents
    # @param mode [Symbol] :import (new only) or :all (re-crawl everything listed)
    def crawl_sitemap(sitemap_xml, limit: nil, mode: :import, fetch_limit: nil)
      products = @parser.parse_sitemap(sitemap_xml)
      known = mode == :import ? known_external_ids(products) : Set.new

      stats = { examined: 0, saved: 0, failed: 0, skipped: 0, replaced: 0, errors: Hash.new(0),
                fetches: 0, aborted: false, exhausted: false }
      consecutive_failures = 0

      products.each do |product|
        break if limit && stats[:saved] >= limit

        # Only saves count towards limit, so an id region that 404s or answers under another mpn would
        # otherwise walk the whole sitemap at one request per second.
        if fetch_limit && stats[:fetches] >= fetch_limit
          stats[:exhausted] = true
          Rails.logger.error("SmdCrawler: fetch budget of #{fetch_limit} spent on #{stats[:saved]} saves")
          Sentry.capture_message("SmdCrawler fetch budget exhausted", level: :warning, extra: stats) if Sentry.initialized?
          break
        end

        stats[:examined] += 1

        if should_skip?(mode, known.include?(product[:id].to_s))
          stats[:skipped] += 1
          next
        end

        result = crawl_product(product[:id])
        stats[:fetches] += 1

        if result[:success]
          # save_product keys on the mpn SMD answered with, so a replaced id never becomes a skip and is re-crawled forever.
          stats[:replaced] += 1 if result[:metadata][:external_id].to_s != product[:id].to_s
          save_product(result[:metadata])
          known << product[:id].to_s
          consecutive_failures = 0
          stats[:saved] += 1
        else
          consecutive_failures += 1 if self.class.blocking_error?(result[:error])
          stats[:failed] += 1
          stats[:errors][result[:error]] += 1
          Rails.logger.warn("Failed to crawl #{product[:id]}: #{result[:error]}")
        end

        # Failures never reach the limit, so a blocked run would walk all 253k products.
        if consecutive_failures >= MAX_CONSECUTIVE_FAILURES
          stats[:aborted] = true
          Rails.logger.error("SmdCrawler: aborting sitemap after #{consecutive_failures} consecutive failures")
          Sentry.capture_message("SmdCrawler aborted", level: :error, extra: stats) if Sentry.initialized?
          break
        end
      end

      stats
    end

    # Crawl from a sitemap URL
    def crawl_sitemap_url(sitemap_url, limit: nil, mode: :import, fetch_limit: nil)
      result = @fetcher.fetch(sitemap_url)
      raise "Failed to fetch sitemap: #{result[:error]}" unless result[:success]

      crawl_sitemap(result[:body], limit: limit, mode: mode, fetch_limit: fetch_limit)
    end

    # Crawl all sitemaps from an index URL
    def crawl_index(index_url, sitemap_limit: nil, product_limit: nil, mode: :import)
      result = @fetcher.fetch(index_url)
      raise "Failed to fetch index: #{result[:error]}" unless result[:success]

      sitemap_urls = @parser.parse_index(result[:body])
      sitemap_urls = sitemap_urls.first(sitemap_limit) if sitemap_limit

      total_stats = { examined: 0, saved: 0, failed: 0, skipped: 0, replaced: 0, errors: Hash.new(0),
                      fetches: 0, sitemaps: 0, aborted: false, exhausted: false }
      fetch_budget = product_limit && product_limit * MAX_FETCHES_PER_SAVE

      sitemap_urls.each do |sitemap_url|
        break if product_limit && product_limit <= 0
        break if fetch_budget && fetch_budget <= 0

        Rails.logger.info("Crawling sitemap: #{sitemap_url}")
        stats = crawl_sitemap_url(sitemap_url, limit: product_limit, mode: mode, fetch_limit: fetch_budget)

        total_stats[:sitemaps] += 1
        total_stats[:examined] += stats[:examined]
        total_stats[:saved] += stats[:saved]
        total_stats[:failed] += stats[:failed]
        total_stats[:skipped] += stats[:skipped]
        total_stats[:replaced] += stats[:replaced]
        total_stats[:fetches] += stats[:fetches]
        stats[:errors].each { |error, count| total_stats[:errors][error] += count }
        total_stats[:aborted] ||= stats[:aborted]
        total_stats[:exhausted] ||= stats[:exhausted]

        product_limit -= stats[:saved] if product_limit
        fetch_budget -= stats[:fetches] if fetch_budget

        Rails.logger.info("Sitemap complete: #{stats}")

        break if stats[:aborted] || stats[:exhausted]
      end

      total_stats
    end

    private

    def product?(metadata)
      metadata[:external_id].present? && metadata[:title].present?
    end

    # Unscoped on purpose: a soft-deleted row must still count as known, or :import re-crawls it daily.
    def known_external_ids(products)
      Score.where(source: "smd", external_id: products.map { |product| product[:id].to_s })
           .pluck(:external_id)
           .to_set
    end

    def should_skip?(mode, exists)
      case mode
      when :import then exists
      when :all then false
      end
    end

    # Map SMD German tags to period, most specific wins
    # Tags are dash-separated and can include multiple period hints
    def smd_period(tags)
      return "Modern" if tags.blank?
      return "Renaissance" if tags.include?("Renaissance")
      return "Baroque" if tags.include?("Barock")
      return "Classical" if tags.include?("Klassik")

      "Modern"
    end

    # Map SMD difficulty labels to pedagogical grades
    # "beginner" → "Grade 1", "elementary" → "Grade 2-3", nil → nil
    def map_difficulty_to_grade(difficulty)
      return nil if difficulty.nil?

      grades = Score::DIFFICULTY_LEVELS[difficulty]
      grades&.first
    end
  end
end
