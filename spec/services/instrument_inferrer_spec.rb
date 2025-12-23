# frozen_string_literal: true

require "rails_helper"

RSpec.describe InstrumentInferrer do
  let(:client) { instance_double(LlmClient) }
  let(:inferrer) { described_class.new(client: client) }
  let(:score) { create(:score, title: "Piano Sonata No. 14", composer: "Beethoven, Ludwig van") }

  describe "#infer" do
    it "returns instruments from LLM response" do
      allow(client).to receive(:chat_json).and_return({ "instruments" => "Piano", "confidence" => "high" })

      result = inferrer.infer(score)

      expect(result.instruments).to eq("Piano")
      expect(result).to be_found
    end

    it "handles null response" do
      allow(client).to receive(:chat_json).and_return({ "instruments" => nil, "confidence" => nil })

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
