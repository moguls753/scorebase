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

    # Cloudflare serves its JS challenge as 200 with no product markup.
    it "rejects a 200 that carries no product markup" do
      stub_request(:get, url).to_return(
        status: 200, body: "<html><head><title>Just a moment...</title></head><body></body></html>"
      )

      result = crawler.crawl_product(product_id)

      expect(result[:success]).to be false
      expect(result[:error]).to eq("unparseable")
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

    it "stamps last_crawled_at" do
      crawler.save_product(metadata)

      expect(Score.last.last_crawled_at).to be_within(5.seconds).of(Time.current)
    end

    it "keeps a normalizer-derived pedagogical_grade when SMD ships no difficulty" do
      Score.create!(external_id: "123456", source: "smd", title: "Old",
                    pedagogical_grade: "Grade 4-5", grade_status: "normalized")

      crawler.save_product(metadata.except(:difficulty))

      expect(Score.find_by(external_id: "123456", source: "smd").pedagogical_grade).to eq("Grade 4-5")
    end

    it "keeps normalizer-derived instruments when SMD ships them blank" do
      Score.create!(external_id: "123456", source: "smd", title: "Old",
                    instruments: "Trumpet", instruments_status: "normalized")

      crawler.save_product(metadata.merge(instruments: ""))

      expect(Score.find_by(external_id: "123456", source: "smd").instruments).to eq("Trumpet")
    end

    it "leaves composer alone on an existing score so hub membership survives" do
      Score.create!(external_id: "123456", source: "smd", title: "Old", composer: "Eilish, Billie")

      crawler.save_product(metadata.merge(composer: "Billie Eilish"))

      expect(Score.find_by(external_id: "123456", source: "smd").composer).to eq("Eilish, Billie")
    end

    it "still updates commercial fields on an existing score" do
      Score.create!(external_id: "123456", source: "smd", title: "Old", price_usd: 7.79)

      crawler.save_product(metadata.merge(price_usd: 5.99))

      expect(Score.find_by(external_id: "123456", source: "smd").price_usd).to eq(5.99)
    end

    it "writes the full attribute set for a score it has never seen" do
      crawler.save_product(metadata.merge(composer: "Billie Eilish"))

      expect(Score.find_by(external_id: "123456", source: "smd").composer).to eq("Billie Eilish")
    end


    it "never nulls an existing value with a field SMD did not ship" do
      Score.create!(external_id: "123456", source: "smd", title: "Old",
                    price_usd: 7.79, rating: 4.5, review_count: 12)

      # ld+json parsed, but `offers` absent — price comes back nil
      crawler.save_product(metadata.merge(price_usd: nil, rating: nil, review_count: nil))

      score = Score.find_by(external_id: "123456", source: "smd")
      expect(score.price_usd).to eq(7.79)
      expect(score.rating).to eq(4.5)
      expect(score.review_count).to eq(12)
    end

    it "does not touch instruments on an existing score even when SMD sends a value" do
      Score.create!(external_id: "123456", source: "smd", title: "Old", instruments: "Trumpet")

      crawler.save_product(metadata.merge(instruments: "Piano"))

      # SmdStatusNormalizer owns this field; the crawler must not fight it.
      expect(Score.find_by(external_id: "123456", source: "smd").instruments).to eq("Trumpet")
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

      expect(stats[:examined]).to eq(2)
      expect(stats[:saved]).to eq(2)
      expect(stats[:failed]).to eq(0)
    end

    it "protects enrichment in :all mode, which re-crawls scores we already hold" do
      Score.create!(external_id: "111", source: "smd", title: "Old",
                    composer: "Eilish, Billie", instruments: "Orchestra")

      crawler.crawl_sitemap(sitemap_xml, mode: :all)

      score = Score.find_by(external_id: "111", source: "smd")
      expect(score.composer).to eq("Eilish, Billie")
      expect(score.instruments).to eq("Orchestra")
    end

    it "respects limit parameter" do
      stats = crawler.crawl_sitemap(sitemap_xml, limit: 1)

      expect(stats[:saved]).to eq(1)
    end

    it "skips existing products in import mode" do
      Score.create!(external_id: "111", source: "smd", title: "Already exists")

      stats = crawler.crawl_sitemap(sitemap_xml, limit: 2, mode: :import)

      expect(stats[:skipped]).to eq(1)
      expect(stats[:saved]).to eq(1)
    end

    it "processes all products in all mode" do
      Score.create!(external_id: "111", source: "smd", title: "Already exists")

      stats = crawler.crawl_sitemap(sitemap_xml, limit: 2, mode: :all)

      expect(stats[:skipped]).to eq(0)
      expect(stats[:saved]).to eq(2)
    end
  end
end
