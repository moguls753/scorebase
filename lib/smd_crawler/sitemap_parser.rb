# frozen_string_literal: true

require "cgi"
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

    # Parse sitemap XML, return list of product hashes with :id and :url.
    # Streamed, not a DOM: SMD's sitemaps hold 50k urls in 28 MB, and Nokogiri::XML added ~310 MB
    # resident for one of them — enough to OOM the 1 GB job container mid-crawl.
    def parse_sitemap(xml)
      products = []
      Nokogiri::XML::Reader(xml).each do |node|
        next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT && node.name == "loc"

        # Reader#inner_xml hands back raw markup where the DOM's #text decoded entities.
        url = CGI.unescapeHTML(node.inner_xml)
        id = extract_product_id(url)
        products << { id: id, url: url } if id
      end
      products
    end

    # Extract product ID from URL, or nil if not a product URL
    def extract_product_id(url)
      match = url.match(PRODUCT_URL_PATTERN)
      match[1] if match
    end
  end
end
