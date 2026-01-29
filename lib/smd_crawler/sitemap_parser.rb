# frozen_string_literal: true

require "nokogiri"

module SmdCrawler
  class SitemapParser
    PRODUCT_URL_PATTERN = %r{/se/ID_No/(\d+)/Product\.aspx}

    # Parse sitemap index XML, return list of sitemap URLs
    def parse_index(xml)
      doc = Nokogiri::XML(xml)
      doc.remove_namespaces!

      doc.xpath("//sitemap/loc").map(&:text)
    end

    # Parse sitemap XML, return list of product hashes with :id and :url
    def parse_sitemap(xml)
      doc = Nokogiri::XML(xml)
      doc.remove_namespaces!

      doc.xpath("//url/loc").filter_map do |loc|
        url = loc.text
        id = extract_product_id(url)
        { id: id, url: url } if id
      end
    end

    # Extract product ID from URL, or nil if not a product URL
    def extract_product_id(url)
      match = url.match(PRODUCT_URL_PATTERN)
      match[1] if match
    end
  end
end
