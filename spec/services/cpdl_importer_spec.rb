# frozen_string_literal: true

require "rails_helper"

RSpec.describe CpdlImporter do
  let(:importer) { described_class.new }

  describe "#score_page?" do
    it "accepts titles with composer in parens" do
      expect(importer.send(:score_page?, "Ave Maria (Bach, Johann Sebastian)")).to be true
    end

    it "rejects disambiguation pages" do
      expect(importer.send(:score_page?, "Ave Maria (disambiguation)")).to be false
    end

    it "rejects composer info pages" do
      expect(importer.send(:score_page?, "Bach (composer)")).to be false
    end

    it "rejects publisher pages" do
      expect(importer.send(:score_page?, "Foo (publisher)")).to be false
    end

    it "rejects book / collection pages" do
      expect(importer.send(:score_page?, "Geistliche Lieder (book)")).to be false
    end

    it "rejects namespace prefixes" do
      expect(importer.send(:score_page?, "Category:Bach")).to be false
      expect(importer.send(:score_page?, "Template:Voicing")).to be false
    end
  end

  describe "#parse_score_metadata (content gate)" do
    it "returns nil when wikitext is empty (stub page)" do
      page_data = { "wikitext" => { "*" => "" }, "categories" => [], "title" => "Foo (Bar)" }
      expect(importer.send(:parse_score_metadata, "Foo (Bar)", page_data)).to be_nil
    end

    it "returns nil when wikitext has no score signals" do
      page_data = { "wikitext" => { "*" => "Just a description, nothing else." },
                    "categories" => [], "title" => "Foo (Bar)" }
      expect(importer.send(:parse_score_metadata, "Foo (Bar)", page_data)).to be_nil
    end

    it "produces metadata when wikitext has a File: reference" do
      wikitext = "[[File:Bach-AveMaria.pdf]]"
      page_data = { "wikitext" => { "*" => wikitext }, "categories" => [], "title" => "Ave Maria (Bach)" }
      allow(importer).to receive(:fetch_file_urls).and_return(pdf: "https://x", midi: nil, musicxml: nil)
      result = importer.send(:parse_score_metadata, "Ave Maria (Bach)", page_data)
      expect(result).not_to be_nil
      expect(result[:title]).to eq("Ave Maria")
    end

    it "produces metadata when wikitext has a {{Voicing}} template only" do
      page_data = { "wikitext" => { "*" => "{{Voicing|4|SATB}}" },
                    "categories" => [], "title" => "Foo (Bar)" }
      allow(importer).to receive(:fetch_file_urls).and_return(pdf: nil, midi: nil, musicxml: nil)
      result = importer.send(:parse_score_metadata, "Foo (Bar)", page_data)
      expect(result).not_to be_nil
      expect(result[:voicing]).to eq("SATB")
      expect(result[:num_parts]).to eq(4)
    end
  end

  describe "#parse_score_metadata (canonical title)" do
    it "uses the canonical title from page_data, not the requested title" do
      page_data = { "wikitext" => { "*" => "[[File:x.pdf]]" },
                    "categories" => [],
                    "title" => "Real Title (Composer)" }
      allow(importer).to receive(:fetch_file_urls).and_return(pdf: "https://x", midi: nil, musicxml: nil)
      result = importer.send(:parse_score_metadata, "Redirect Source (Foo)", page_data)
      expect(result[:title]).to eq("Real Title")
      expect(result[:canonical_title]).to eq("Real Title (Composer)")
    end
  end

  describe "#fetch_page_content" do
    it "passes redirects=1 in the API params" do
      allow(importer).to receive(:api_request) do |params|
        expect(params).to include(redirects: 1)
        { "title" => "Real (Composer)", "wikitext" => { "*" => "" }, "categories" => [] }
      end
      importer.send(:fetch_page_content, "Redirect Source")
      expect(importer).to have_received(:api_request)
    end
  end
end
