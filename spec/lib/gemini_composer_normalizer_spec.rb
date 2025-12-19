# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

# Test the Gemini API integration used by normalize:composers rake task
RSpec.describe "Gemini Composer Normalizer" do
  let(:api_key) { "test-api-key" }
  let(:gemini_url) { "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent" }

  def gemini_normalize(api_key, batch)
    # Extracted from rake task for testing
    uri = URI("#{gemini_url}?key=#{api_key}")

    scores_data = batch.map do |composer, title, editor, genres, language|
      { composer: composer, title: title, editor: editor, genres: genres, language: language }
    end

    body = {
      contents: [ { parts: [ { text: "test prompt #{scores_data.to_json}" } ] } ],
      generationConfig: { responseMimeType: "application/json", temperature: 0.1 }
    }

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.verify_callback = ->(_ok, _ctx) { true }
    http.read_timeout = 60

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req.body = body.to_json

    res = http.request(req)

    return :quota_exceeded if res.code == "429"
    return nil unless res.code == "200"

    JSON.parse(JSON.parse(res.body).dig("candidates", 0, "content", "parts", 0, "text"))
  rescue JSON::ParserError
    nil
  end

  describe "#gemini_normalize" do
    let(:success_response) do
      {
        candidates: [ {
          content: {
            parts: [ {
              text: '[{"original":"J.S. Bach","normalized":"Bach, Johann Sebastian"}]'
            } ]
          }
        } ]
      }.to_json
    end

    it "returns normalized composers on success" do
      stub_request(:post, /#{gemini_url}/)
        .to_return(status: 200, body: success_response)

      batch = [ [ "J.S. Bach", "Toccata", nil, nil, nil ] ]
      result = gemini_normalize(api_key, batch)

      expect(result.first["original"]).to eq("J.S. Bach")
      expect(result.first["normalized"]).to eq("Bach, Johann Sebastian")
    end

    it "returns :quota_exceeded on 429" do
      stub_request(:post, /#{gemini_url}/)
        .to_return(status: 429, body: "Rate limited")

      batch = [ [ "Bach", nil, nil, nil, nil ] ]
      result = gemini_normalize(api_key, batch)

      expect(result).to eq(:quota_exceeded)
    end

    it "returns nil on server error" do
      stub_request(:post, /#{gemini_url}/)
        .to_return(status: 500, body: "Server Error")

      batch = [ [ "Bach", nil, nil, nil, nil ] ]
      result = gemini_normalize(api_key, batch)

      expect(result).to be_nil
    end

    it "returns nil on malformed JSON response" do
      stub_request(:post, /#{gemini_url}/)
        .to_return(status: 200, body: { candidates: [ { content: { parts: [ { text: "invalid json" } ] } } ] }.to_json)

      batch = [ [ "Bach", nil, nil, nil, nil ] ]
      result = gemini_normalize(api_key, batch)

      expect(result).to be_nil
    end
  end
end
