# frozen_string_literal: true

require "rails_helper"

RSpec.describe PeriodFromTitleInferrer do
  let(:client) { instance_double(LlmClient) }
  let(:inferrer) { described_class.new(client: client) }
  let(:score) { create(:score, title: "Ave maris stella", composer: "Traditional", composer_status: "failed") }

  describe "#infer" do
    it "returns period from LLM response" do
      allow(client).to receive(:chat_json).and_return({ "period" => "Renaissance", "confidence" => "high" })

      result = inferrer.infer(score)

      expect(result.period).to eq("Renaissance")
      expect(result).to be_found
    end

    it "handles null response" do
      allow(client).to receive(:chat_json).and_return({ "period" => nil, "confidence" => "none" })

      result = inferrer.infer(score)

      expect(result).to be_success
      expect(result).not_to be_found
    end

    it "handles errors gracefully" do
      allow(client).to receive(:chat_json).and_raise(LlmClient::Error, "API down")

      result = inferrer.infer(score)

      expect(result).not_to be_success
      expect(result.error).to eq("API down")
    end
  end
end
