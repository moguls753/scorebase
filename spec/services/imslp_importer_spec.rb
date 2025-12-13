# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe ImslpImporter do
  let(:importer) { described_class.new }
  let(:api_key) { "test-api-key" }
  let(:gemini_url) { "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent" }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("GEMINI_API_KEY").and_return(api_key)

    # Clear cache before each test
    cache_file = Rails.root.join("tmp", "composer_normalizer_cache.json")
    File.delete(cache_file) if File.exist?(cache_file)
  end

  describe "#normalize_composer" do
    it "returns nil for blank input" do
      expect(importer.send(:normalize_composer, nil)).to be_nil
      expect(importer.send(:normalize_composer, "")).to be_nil
    end

    it "returns cached value if exists" do
      cache_file = Rails.root.join("tmp", "composer_normalizer_cache.json")
      File.write(cache_file, { "Bach" => "Bach, Johann Sebastian" }.to_json)

      expect(importer.send(:normalize_composer, "Bach")).to eq("Bach, Johann Sebastian")
    end

    it "queues uncached composers for batch processing" do
      importer.send(:normalize_composer, "Mozart")
      expect(importer.instance_variable_get(:@composer_queue)).to include("Mozart")
    end
  end

  describe "#gemini_normalize_batch" do
    let(:success_response) do
      {
        candidates: [{
          content: {
            parts: [{
              text: '[{"original":"Bach","normalized":"Bach, Johann Sebastian"}]'
            }]
          }
        }]
      }.to_json
    end

    it "returns parsed JSON on success" do
      stub_request(:post, /#{gemini_url}/)
        .to_return(status: 200, body: success_response)

      result = importer.send(:gemini_normalize_batch, api_key, ["Bach"])

      expect(result).to be_an(Array)
      expect(result.first["original"]).to eq("Bach")
      expect(result.first["normalized"]).to eq("Bach, Johann Sebastian")
    end

    it "returns nil on API error" do
      stub_request(:post, /#{gemini_url}/)
        .to_return(status: 500, body: "Server Error")

      result = importer.send(:gemini_normalize_batch, api_key, ["Bach"])
      expect(result).to be_nil
    end

    it "handles malformed JSON gracefully" do
      stub_request(:post, /#{gemini_url}/)
        .to_return(status: 200, body: { candidates: [{ content: { parts: [{ text: "not json" }] } }] }.to_json)

      result = importer.send(:gemini_normalize_batch, api_key, ["Bach"])
      expect(result).to be_nil
    end
  end
end
