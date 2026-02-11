# frozen_string_literal: true

require "rails_helper"

RSpec.describe PeriodFromTitleInferrer do
  let(:client) { instance_double(LlmClient) }
  let(:inferrer) { described_class.new(client: client) }

  describe "#infer" do
    it "returns period from LLM response" do
      score = create(:score, title: "Ave maris stella", composer: "Traditional")
      allow(client).to receive(:chat_json).and_return({ "period" => "Renaissance", "confidence" => "high" })

      results = inferrer.infer(score)

      expect(results.first.period).to eq("Renaissance")
      expect(results.first).to be_found
    end

    it "handles null response" do
      score = create(:score, title: "Unknown Work")
      allow(client).to receive(:chat_json).and_return({ "period" => nil, "confidence" => "none" })

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
      allow(client).to receive(:chat_json).and_return({
        "results" => [
          { "id" => 1, "period" => "Renaissance", "confidence" => "low" },
          { "id" => 2, "period" => "Classical", "confidence" => "high" }
        ]
      })

      results = inferrer.infer(scores)

      expect(results.length).to eq(2)
      expect(results[0].period).to eq("Renaissance")
      expect(results[1].period).to eq("Classical")
    end

    it "returns empty array for empty input" do
      expect(inferrer.infer([])).to eq([])
    end
  end
end
