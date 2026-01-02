# frozen_string_literal: true

require "rails_helper"

RSpec.describe PeriodFromTitleInferrer do
  let(:client) { instance_double(LlmClient) }
  let(:inferrer) { described_class.new(client: client) }
  let(:score) { create(:score, title: "Ave maris stella", composer: "Traditional", composer_status: "failed") }

  describe "#infer" do
    it "returns period from LLM response" do
      allow(client).to receive(:chat_json).and_return({ "period" => "Renaissance", "confidence" => "high" })

      results = inferrer.infer(score)

      expect(results).to be_an(Array)
      expect(results.first.period).to eq("Renaissance")
      expect(results.first).to be_found
    end

    it "includes composer in prompt" do
      expect(client).to receive(:chat_json) do |prompt|
        expect(prompt).to include("Composer: Traditional")
        { "period" => "Renaissance", "confidence" => "high" }
      end

      inferrer.infer(score)
    end

    it "handles null response" do
      allow(client).to receive(:chat_json).and_return({ "period" => nil, "confidence" => "none" })

      results = inferrer.infer(score)

      expect(results.first).to be_success
      expect(results.first).not_to be_found
    end

    it "handles errors gracefully" do
      allow(client).to receive(:chat_json).and_raise(LlmClient::Error, "API down")

      results = inferrer.infer(score)

      expect(results.first).not_to be_success
      expect(results.first.error).to eq("API down")
    end

    it "processes multiple scores in batch" do
      score2 = create(:score, title: "Moonlight Sonata", composer: "Beethoven")

      allow(client).to receive(:chat_json).and_return({
        "results" => [
          { "id" => 1, "period" => "Renaissance", "confidence" => "low" },
          { "id" => 2, "period" => "Classical", "confidence" => "high" }
        ]
      })

      results = inferrer.infer([score, score2])

      expect(results.length).to eq(2)
      expect(results[0].period).to eq("Renaissance")
      expect(results[1].period).to eq("Classical")
    end

    it "returns empty array for empty input" do
      results = inferrer.infer([])
      expect(results).to eq([])
    end
  end
end
