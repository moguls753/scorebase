# frozen_string_literal: true

require "rails_helper"

RSpec.describe InstrumentInferrer do
  let(:client) { instance_double(LlmClient) }
  let(:inferrer) { described_class.new(client: client) }

  describe "#infer" do
    it "returns instruments from LLM response" do
      score = create(:score, title: "Piano Sonata No. 14", composer: "Beethoven, Ludwig van")
      allow(client).to receive(:chat_json).and_return({ "instruments" => "Piano", "confidence" => "high" })

      results = inferrer.infer(score)

      expect(results.first.instruments).to eq("Piano")
      expect(results.first).to be_found
    end

    it "handles null response" do
      score = create(:score, title: "Unknown Work")
      allow(client).to receive(:chat_json).and_return({ "instruments" => nil, "confidence" => nil })

      expect(inferrer.infer(score).first).not_to be_found
    end

    it "handles errors gracefully" do
      score = create(:score, title: "Test")
      allow(client).to receive(:chat_json).and_raise(LlmClient::Error, "API down")

      results = inferrer.infer(score)

      expect(results.first).not_to be_success
      expect(results.first.error).to eq("API down")
    end

    it "processes multiple scores in batch" do
      scores = create_list(:score, 2)
      allow(client).to receive(:chat_json_array).and_return([
        { "id" => 1, "instruments" => "Piano", "confidence" => "high" },
        { "id" => 2, "instruments" => "Guitar", "confidence" => "high" }
      ])

      results = inferrer.infer(scores)

      expect(results.length).to eq(2)
      expect(results[0].instruments).to eq("Piano")
      expect(results[1].instruments).to eq("Guitar")
    end

    it "returns empty array for empty input" do
      expect(inferrer.infer([])).to eq([])
    end
  end
end
