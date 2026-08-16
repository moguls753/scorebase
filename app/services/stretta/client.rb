# frozen_string_literal: true

require "net/http"

# Stretta's Shopify Storefront API (docs/stretta-api-evidence-2026-08-14.md).
#
# Products are fetched one handle at a time, aliased in batches: the `products`
# connection is capped at 25,000 elements under every sort key, so no paginated
# full pass exists. `products(sortKey: CREATED_AT)` is only used for new arrivals,
# where the weekly volume stays far below the cap.
module Stretta
  class Client
    ENDPOINT = "https://stretta-dev.myshopify.com/api/2025-07/graphql.json"

    # Public by construction — Hydrogen ships it in the page source. In credentials
    # only so a rotation does not need a deploy.
    DEFAULT_TOKEN = "d1f7f03ccef19433c2258506ae11b6df"

    BATCH_SIZE = 50
    MAX_ATTEMPTS = 4
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 60

    # One batch that will not come back after its retries is 50 products out of a
    # million — worth losing. A run of them is the shop being down or the token
    # having rotated, and continuing then writes a thinned catalogue.
    MAX_CONSECUTIVE_FAILURES = 5

    class Error < StandardError; end
    class Aborted < StandardError; end

    PRODUCT_FIELDS = <<~GRAPHQL
      handle
      title
      vendor
      productType
      availableForSale
      createdAt
      featuredImage { url }
      priceRange { minVariantPrice { amount } }
      compareAtPriceRange { minVariantPrice { amount } }
      texts: metafield(namespace: "custom", key: "texts") { value }
      orderNo: metafield(namespace: "custom", key: "order_no") { value }
      bulkPrices: metafield(namespace: "custom", key: "bulk_prices") { value }
      minQuantity: metafield(namespace: "custom", key: "minquantity") { value }
      difficulty: metafield(namespace: "custom", key: "difficulty") { value }
      pages: metafield(namespace: "custom", key: "pages") { value }
      ismn: metafield(namespace: "facts", key: "ismn") { value }
      isbn: metafield(namespace: "facts", key: "isbn") { value }
      previewPdfs: metafield(namespace: "preview", key: "pdfs") { value }
      slugs: metafield(namespace: "stretta", key: "slugs") { value }
      facets: metafield(namespace: "stretta", key: "facets") { value }
    GRAPHQL

    def initialize(token: nil, batch_size: BATCH_SIZE, logger: Rails.logger)
      @token = token || Rails.application.credentials.dig(:stretta, :storefront_token) || DEFAULT_TOKEN
      @batch_size = batch_size
      @logger = logger
    end

    # Products for the given handles, in batches. Handles the API no longer knows
    # are simply absent from the result — 8.2% of sitemap ids are dead.
    def products(handles)
      return enum_for(:products, handles) unless block_given?

      consecutive_failures = 0
      handles.each_slice(@batch_size) do |batch|
        begin
          data = post(batch_query(batch))
        rescue Error => e
          consecutive_failures += 1
          raise Aborted, "#{consecutive_failures} batches in a row failed: #{e.message}" if
            consecutive_failures >= MAX_CONSECUTIVE_FAILURES

          @logger.warn "[Stretta::Client] batch failed (#{consecutive_failures}/#{MAX_CONSECUTIVE_FAILURES}): #{e.message}"
          next
        end

        consecutive_failures = 0
        batch.each_with_index do |handle, index|
          node = data["p#{index}"]
          yield Product.from_graphql(node) if node
        end
      end
    end

    # Newest first, for the weekly pass. The caller decides when to stop (by
    # breaking out) — a date watermark cannot work here, because our created_at is
    # when we imported a row, not when Stretta created the product.
    def newest_first(page_size: 250, max_pages: 100)
      return enum_for(:newest_first, page_size: page_size, max_pages: max_pages) unless block_given?

      cursor = nil
      max_pages.times do
        data = post(recent_query(page_size, cursor))
        connection = data.fetch("products")
        connection.fetch("nodes").each { |node| yield Product.from_graphql(node) }

        page = connection.fetch("pageInfo")
        return unless page["hasNextPage"]

        cursor = page["endCursor"]
      end
    end

    private

    def batch_query(handles)
      aliases = handles.each_with_index.map do |handle, index|
        %(p#{index}: product(handle: #{handle.to_s.to_json}) { #{PRODUCT_FIELDS} })
      end
      "{ #{aliases.join("\n")} }"
    end

    def recent_query(page_size, cursor)
      after = cursor ? ", after: #{cursor.to_json}" : ""
      <<~GRAPHQL
        { products(first: #{page_size}, sortKey: CREATED_AT, reverse: true#{after}) {
            nodes { #{PRODUCT_FIELDS} }
            pageInfo { hasNextPage endCursor }
        } }
      GRAPHQL
    end

    def post(query)
      attempt = 0
      begin
        attempt += 1
        body = JSON.parse(request(query).body)
        data = body["data"]
        # A batch-wide failure still comes back as {"p0"=>nil, "p1"=>nil, ...} — a
        # Hash#blank? check alone misses it, since a Hash with keys is never blank
        # however many of its values are nil, and that shape would otherwise read
        # as "50 products confirmed absent" instead of "the batch failed".
        no_usable_data = data.blank? || data.values.all?(&:blank?)
        raise Error, body["errors"].to_s if body["errors"].present? && no_usable_data

        body.fetch("data")
      rescue Error, JSON::ParserError, KeyError, Net::HTTPBadResponse, IOError, SystemCallError, Timeout::Error => e
        raise Error, "#{e.class}: #{e.message}" if attempt >= MAX_ATTEMPTS

        @logger.warn "[Stretta::Client] attempt #{attempt} failed (#{e.class}), retrying"
        sleep(2**attempt)
        retry
      end
    end

    def request(query)
      uri = URI(ENDPOINT)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      post = Net::HTTP::Post.new(uri)
      post["Content-Type"] = "application/json"
      post["X-Shopify-Storefront-Access-Token"] = @token
      post.body = { query: query }.to_json

      response = http.request(post)
      raise Error, "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      response
    end
  end
end
