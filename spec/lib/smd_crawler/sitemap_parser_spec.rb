# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmdCrawler::SitemapParser do
  describe "#parse_index" do
    let(:parser) { described_class.new }

    let(:index_xml) do
      <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <sitemap>
            <loc>https://www.sheetmusicdirect.com/sitemaps/prodHL-sitemap1.xml</loc>
          </sitemap>
          <sitemap>
            <loc>https://www.sheetmusicdirect.com/sitemaps/prodHL-sitemap2.xml</loc>
          </sitemap>
        </sitemapindex>
      XML
    end

    it "extracts sitemap URLs from index" do
      urls = parser.parse_index(index_xml)

      expect(urls).to eq([
        "https://www.sheetmusicdirect.com/sitemaps/prodHL-sitemap1.xml",
        "https://www.sheetmusicdirect.com/sitemaps/prodHL-sitemap2.xml"
      ])
    end
  end

  describe "#parse_sitemap" do
    let(:parser) { described_class.new }

    let(:sitemap_xml) do
      <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <urlset xmlns:xhtml="http://www.w3.org/1999/xhtml" xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <url>
            <loc>https://www.sheetmusicdirect.com/se/ID_No/1925090/Product.aspx</loc>
            <xhtml:link rel="alternate" hreflang="en" href="https://www.sheetmusicdirect.com/se/ID_No/1925090/Product.aspx" />
          </url>
          <url>
            <loc>https://www.sheetmusicdirect.com/se/ID_No/1925089/Product.aspx</loc>
            <xhtml:link rel="alternate" hreflang="en" href="https://www.sheetmusicdirect.com/se/ID_No/1925089/Product.aspx" />
          </url>
        </urlset>
      XML
    end

    it "extracts product IDs from sitemap" do
      products = parser.parse_sitemap(sitemap_xml)

      expect(products).to eq([
        { id: "1925090", url: "https://www.sheetmusicdirect.com/se/ID_No/1925090/Product.aspx" },
        { id: "1925089", url: "https://www.sheetmusicdirect.com/se/ID_No/1925089/Product.aspx" }
      ])
    end

    it "skips non-product URLs" do
      xml_with_mixed = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <url>
            <loc>https://www.sheetmusicdirect.com/se/ID_No/1925090/Product.aspx</loc>
          </url>
          <url>
            <loc>https://www.sheetmusicdirect.com/about-us</loc>
          </url>
        </urlset>
      XML

      products = parser.parse_sitemap(xml_with_mixed)

      expect(products.length).to eq(1)
      expect(products.first[:id]).to eq("1925090")
    end
  end

  describe "#extract_product_id" do
    let(:parser) { described_class.new }

    it "extracts ID from standard product URL" do
      url = "https://www.sheetmusicdirect.com/se/ID_No/1925090/Product.aspx"
      expect(parser.extract_product_id(url)).to eq("1925090")
    end

    it "returns nil for non-product URLs" do
      expect(parser.extract_product_id("https://www.sheetmusicdirect.com/about")).to be_nil
    end
  end
end
