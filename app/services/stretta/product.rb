# frozen_string_literal: true

# The one shape Classifier, Grouping and ProductMapper consume. Built here so a
# response-format change lands in a single place.
#
# custom.texts carries the fields that matter: the product `title` is truncated to
# a fixed length by the shop ("…so ist a" vs "…so ist au" for the same work), so
# the work title is read from texts.title and never from the product title.
module Stretta
  class Product
    ROLE_KEYS = %i[role name slug bio].freeze

    def self.from_graphql(node)
      texts = parse_json(node.dig("texts", "value")) || {}

      {
        handle: node["handle"],
        product_title: node["title"],
        vendor: node["vendor"],
        product_type: node["productType"],
        available_for_sale: node["availableForSale"] == true,
        created_at: node["createdAt"],
        image_url: node.dig("featuredImage", "url"),
        price: node.dig("priceRange", "minVariantPrice", "amount")&.to_f,
        compare_at_price: node.dig("compareAtPriceRange", "minVariantPrice", "amount")&.to_f,

        title: texts["title"],
        subtitle: texts["subtitle"],
        itemtype: texts["itemtype"],
        instrument: texts["instrument"],
        languages: texts["languages"],
        authors: authors(texts["authors"]),

        order_no: value(node, "orderNo"),
        difficulty: value(node, "difficulty"),
        minquantity: value(node, "minQuantity"),
        ismn: value(node, "ismn"),
        isbn: value(node, "isbn"),
        pages: parse_json(value(node, "pages")),
        bulk_prices: parse_json(value(node, "bulkPrices")),
        slugs: parse_json(value(node, "slugs")),
        facets: parse_json(value(node, "facets")),
        preview_pdf: parse_json(value(node, "previewPdfs")).present?
      }.tap { |product| product[:slug_de] = product[:slugs]&.dig("DE") }
    end

    def self.authors(list)
      Array(list).filter_map do |author|
        next unless author.is_a?(Hash)

        author.symbolize_keys.slice(*ROLE_KEYS)
      end
    end

    def self.value(node, key)
      node.dig(key, "value")
    end

    def self.parse_json(raw)
      return nil if raw.blank?

      JSON.parse(raw)
    rescue JSON::ParserError
      nil
    end
  end
end
