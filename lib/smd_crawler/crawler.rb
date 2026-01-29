# frozen_string_literal: true

require_relative "sitemap_parser"
require_relative "page_fetcher"
require_relative "metadata_extractor"

module SmdCrawler
  class Crawler
    PRODUCT_URL_TEMPLATE = "https://www.sheetmusicdirect.com/se/ID_No/%s/Product.aspx"

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
      { success: true, metadata: metadata }
    end

    # Save product metadata to Score model
    def save_product(metadata)
      score = Score.find_or_initialize_by(
        external_id: metadata[:external_id],
        source: "smd"
      )

      score.assign_attributes(
        title: metadata[:title],
        clean_title: metadata[:clean_title],
        composer: metadata[:composer],
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
        preview_image_url: metadata[:preview_image_url]
      )

      score.save!
      score
    end

    # Crawl all products from a sitemap XML string
    # @param mode [Symbol] :import (new only), :update (existing only), :all (both)
    def crawl_sitemap(sitemap_xml, limit: nil, mode: :import)
      products = @parser.parse_sitemap(sitemap_xml)

      stats = { examined: 0, saved: 0, failed: 0, skipped: 0 }

      products.each do |product|
        break if limit && stats[:saved] >= limit

        stats[:examined] += 1
        exists = Score.exists?(external_id: product[:id], source: "smd")

        if should_skip?(mode, exists)
          stats[:skipped] += 1
          next
        end

        result = crawl_product(product[:id])

        if result[:success]
          save_product(result[:metadata])
          stats[:saved] += 1
        else
          stats[:failed] += 1
          Rails.logger.warn("Failed to crawl #{product[:id]}: #{result[:error]}")
        end
      end

      stats
    end

    # Crawl from a sitemap URL
    def crawl_sitemap_url(sitemap_url, limit: nil, mode: :import)
      result = @fetcher.fetch(sitemap_url)
      raise "Failed to fetch sitemap: #{result[:error]}" unless result[:success]

      crawl_sitemap(result[:body], limit: limit, mode: mode)
    end

    # Crawl all sitemaps from an index URL
    def crawl_index(index_url, sitemap_limit: nil, product_limit: nil, mode: :import)
      result = @fetcher.fetch(index_url)
      raise "Failed to fetch index: #{result[:error]}" unless result[:success]

      sitemap_urls = @parser.parse_index(result[:body])
      sitemap_urls = sitemap_urls.first(sitemap_limit) if sitemap_limit

      total_stats = { examined: 0, saved: 0, failed: 0, skipped: 0, sitemaps: 0 }

      sitemap_urls.each do |sitemap_url|
        break if product_limit&.zero?

        Rails.logger.info("Crawling sitemap: #{sitemap_url}")
        stats = crawl_sitemap_url(sitemap_url, limit: product_limit, mode: mode)

        total_stats[:sitemaps] += 1
        total_stats[:examined] += stats[:examined]
        total_stats[:saved] += stats[:saved]
        total_stats[:failed] += stats[:failed]
        total_stats[:skipped] += stats[:skipped]

        product_limit -= stats[:saved] if product_limit

        Rails.logger.info("Sitemap complete: #{stats}")
      end

      total_stats
    end

    private

    def should_skip?(mode, exists)
      case mode
      when :import then exists
      when :update then !exists
      when :all then false
      end
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
