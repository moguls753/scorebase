# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmdCrawler::MetadataExtractor do
  describe "#extract" do
    let(:extractor) { described_class.new }

    # Realistic HTML structure based on SMD product page ID 1924671
    let(:html) do
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <meta name="twitter:data1" content="2">
          <script>
            window.dataLayer = window.dataLayer || [];
            dataLayer.push({
                'arrangementCategory': 'Easy Piano',
                "artists_contributors_list": ["Jason Howland","Nathan Tysen"],
                "category_level_1": "Digital Sheet Music",
                "category_level_2": "Super Easy Piano",
                "genres_list": ["Broadway"],
                "original_price": 5.39,
                "main_instrument": "Easy Piano"
            });
          </script>
          <script type="application/ld+json">[{"@context":"http://schema.org","@type":"Product","image":{"@type":"ImageObject","thumbnail":"https://img.sheetmusic.direct/catalogue/product/the-great-gatsby-musical-md.jpg"},"name":"For Her (from The Great Gatsby) by Nathan Tysen Super Easy Piano Digital Sheet Music","brand":"Hal Leonard","mpn":1924671,"offers":{"@type":"Offer","priceCurrency":"USD","price":4.79},"additionalProperty":{"@type":"PropertyValue","name":"Instruments","value":["Piano/Keyboard"]}}]</script>
        </head>
        <body></body>
        </html>
      HTML
    end

    it "extracts external_id from JSON-LD mpn field" do
      result = extractor.extract(html)

      expect(result[:external_id]).to eq("1924671")
    end

    it "extracts composer from JS artists_contributors_list" do
      result = extractor.extract(html)

      expect(result[:composer]).to eq("Jason Howland")
      expect(result[:contributors]).to eq(["Jason Howland", "Nathan Tysen"])
    end

    it "extracts tags from JS genres_list (hyphen-delimited)" do
      result = extractor.extract(html)

      expect(result[:tags]).to eq("Broadway")
    end

    it "maps category_level_2 to smd_category and difficulty" do
      result = extractor.extract(html)

      expect(result[:smd_category]).to eq("Super Easy Piano")
      expect(result[:difficulty]).to eq("beginner")
    end

    it "extracts page_count from twitter meta tag" do
      result = extractor.extract(html)

      expect(result[:page_count]).to eq(2)
    end

    it "extracts pitch_range from twitter:data2 meta tag" do
      html_with_range = <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <meta name="twitter:data2" content="C♯4-D6">
          <script type="application/ld+json">[{"@type":"Product","mpn":115612}]</script>
        </head>
        </html>
      HTML

      result = extractor.extract(html_with_range)

      expect(result[:pitch_range]).to eq("C♯4-D6")
    end

    it "sets source to smd" do
      result = extractor.extract(html)

      expect(result[:source]).to eq("smd")
    end

    it "joins multiple genres with hyphen for tags" do
      html_multi_genre = <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <script>
            dataLayer.push({
                "genres_list": ["Baroque","Classical","Halloween"]
            });
          </script>
          <script type="application/ld+json">[{"@type":"Product","mpn":160833}]</script>
        </head>
        </html>
      HTML

      result = extractor.extract(html_multi_genre)

      expect(result[:tags]).to eq("Baroque-Classical-Halloween")
    end

    context "when difficulty is not explicit" do
      let(:html) do
        <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
            <script>
              dataLayer.push({
                  "category_level_2": "Piano Solo"
              });
            </script>
            <script type="application/ld+json">[{"@type":"Product","mpn":160833,"name":"Toccata And Fugue In D Minor"}]</script>
          </head>
          </html>
        HTML
      end

      it "returns nil difficulty (not embedded for semantic search)" do
        result = extractor.extract(html)

        expect(result[:smd_category]).to eq("Piano Solo")
        expect(result[:difficulty]).to be_nil
      end
    end
  end
end
