# frozen_string_literal: true

require "rails_helper"

RSpec.describe VocalDetector do
  let(:client) { instance_double(LlmClient) }
  let(:detector) { described_class.new(client: client) }

  describe "#detect" do
    it "returns has_vocal from LLM response" do
      score = create(:score, title: "Ave Maria", part_names: "Soprano, Alto, Tenor, Bass")
      allow(client).to receive(:chat_json).and_return({ "has_vocal" => true, "confidence" => "high" })

      results = detector.detect(score)

      expect(results.first.has_vocal).to be true
      expect(results.first).to be_success
    end

    it "handles errors gracefully" do
      score = create(:score, title: "Test")
      allow(client).to receive(:chat_json).and_raise(LlmClient::Error, "API down")

      results = detector.detect(score)

      expect(results.first).not_to be_success
      expect(results.first.error).to eq("API down")
    end

    it "processes multiple scores in batch" do
      scores = create_list(:score, 2)
      allow(client).to receive(:chat_json_array).and_return([
        { "id" => 1, "has_vocal" => true, "confidence" => "high" },
        { "id" => 2, "has_vocal" => false, "confidence" => "high" }
      ])

      results = detector.detect(scores)

      expect(results.length).to eq(2)
      expect(results[0].has_vocal).to be true
      expect(results[1].has_vocal).to be false
    end

    it "returns empty array for empty input" do
      expect(detector.detect([])).to eq([])
    end
  end
end
