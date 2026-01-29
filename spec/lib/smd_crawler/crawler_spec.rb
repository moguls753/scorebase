# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe SmdCrawler::Crawler do
  let(:crawler) { described_class.new }

  describe "#crawl_product" do
    let(:product_id) { "1925090" }
    let(:url) { "https://www.sheetmusicdirect.com/se/ID_No/#{product_id}/Product.aspx" }

    let(:html) do
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <meta name="twitter:data1" content="3">
          <script>
            dataLayer.push({
                "category_level_2": "Easy Piano",
                "artists_contributors_list": ["John Williams"],
                "genres_list": ["Film/TV"]
            });
          </script>
          <script type="application/ld+json">[{
            "@type": "Product",
            "mpn": #{product_id},
            "name": "Star Wars Theme",
            "brand": "Hal Leonard",
            "offers": {"price": 5.99}
          }]</script>
        </head>
        </html>
      HTML
    end

    before do
      stub_request(:get, url).to_return(status: 200, body: html)
    end

    it "fetches and extracts metadata for a product" do
      result = crawler.crawl_product(product_id)

      expect(result[:success]).to be true
      expect(result[:metadata][:external_id]).to eq(product_id)
      expect(result[:metadata][:title]).to eq("Star Wars Theme")
      expect(result[:metadata][:composer]).to eq("John Williams")
    end

    it "returns failure when fetch fails" do
      stub_request(:get, url).to_return(status: 404)

      result = crawler.crawl_product(product_id)

      expect(result[:success]).to be false
      expect(result[:error]).to eq("not_found")
    end
  end

  describe "#save_product" do
    let(:metadata) do
      {
        external_id: "123456",
        title: "Test Song",
        composer: "Test Composer",
        tags: "Pop-Rock",
        smd_category: "Easy Piano",
        difficulty: "elementary",
        price_usd: 5.99,
        page_count: 4,
        brand: "Hal Leonard",
        source: "smd"
      }
    end

    it "creates a new Score record" do
      expect {
        crawler.save_product(metadata)
      }.to change(Score, :count).by(1)

      score = Score.last
      expect(score.external_id).to eq("123456")
      expect(score.data_path).to be_nil
      expect(score.title).to eq("Test Song")
      expect(score.composer).to eq("Test Composer")
      expect(score.source).to eq("smd")
    end

    it "maps difficulty to pedagogical_grade" do
      crawler.save_product(metadata)

      score = Score.last
      expect(score.pedagogical_grade).to eq("Grade 2-3") # elementary → first of DIFFICULTY_LEVELS
    end

    it "updates existing Score by external_id and source" do
      Score.create!(external_id: "123456", title: "Old Title", source: "smd")

      expect {
        crawler.save_product(metadata)
      }.not_to change(Score, :count)

      score = Score.find_by(external_id: "123456", source: "smd")
      expect(score.title).to eq("Test Song")
    end

    it "does not update scores from other sources" do
      Score.create!(external_id: "123456", title: "IMSLP Score", source: "imslp")

      expect {
        crawler.save_product(metadata)
      }.to change(Score, :count).by(1)

      expect(Score.where(external_id: "123456").count).to eq(2)
    end
  end

  describe "#crawl_sitemap" do
    let(:sitemap_xml) do
      <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <url><loc>https://www.sheetmusicdirect.com/se/ID_No/111/Product.aspx</loc></url>
          <url><loc>https://www.sheetmusicdirect.com/se/ID_No/222/Product.aspx</loc></url>
        </urlset>
      XML
    end

    let(:product_html) do
      <<~HTML
        <script type="application/ld+json">[{"@type":"Product","mpn":111,"name":"Song","brand":"HL","offers":{"price":5.99}}]</script>
      HTML
    end

    before do
      stub_request(:get, "https://www.sheetmusicdirect.com/se/ID_No/111/Product.aspx")
        .to_return(status: 200, body: product_html.sub("111", "111"))
      stub_request(:get, "https://www.sheetmusicdirect.com/se/ID_No/222/Product.aspx")
        .to_return(status: 200, body: product_html.sub("111", "222"))
    end

    it "crawls all products in a sitemap" do
      stats = crawler.crawl_sitemap(sitemap_xml, limit: 2)

      expect(stats[:total]).to eq(2)
      expect(stats[:success]).to eq(2)
      expect(stats[:failed]).to eq(0)
    end

    it "respects limit parameter" do
      stats = crawler.crawl_sitemap(sitemap_xml, limit: 1)

      expect(stats[:total]).to eq(1)
    end

    it "skips already crawled products" do
      Score.create!(external_id: "111", source: "smd", title: "Already exists")

      stats = crawler.crawl_sitemap(sitemap_xml, limit: 2, skip_existing: true)

      expect(stats[:skipped]).to eq(1)
      expect(stats[:success]).to eq(1)
    end
  end
end
