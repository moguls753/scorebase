# frozen_string_literal: true

require "rails_helper"

RSpec.describe InstrumentInferrer do
  let(:client) { instance_double(LlmClient) }
  let(:inferrer) { described_class.new(client: client) }
  let(:score) { create(:score, title: "Piano Sonata No. 14", composer: "Beethoven, Ludwig van", period: "Classical") }

  describe "#infer" do
    it "returns instruments from LLM response" do
      allow(client).to receive(:chat_json).and_return({ "instruments" => "Piano", "confidence" => "high" })

      result = inferrer.infer(score)

      expect(result.instruments).to eq("Piano")
      expect(result).to be_found
    end

    it "includes period in prompt" do
      score = create(:score, title: "Test", composer: "Bach", period: "Baroque")

      expect(client).to receive(:chat_json) do |prompt|
        expect(prompt).to include("Period: Baroque")
        { "instruments" => "Organ", "confidence" => "medium" }
      end

      inferrer.infer(score)
    end

    it "includes composer in prompt for instrument hints" do
      score = create(:score, title: "Etude", composer: "Sor, Fernando", period: "Classical")

      expect(client).to receive(:chat_json) do |prompt|
        expect(prompt).to include("Composer: Sor, Fernando")
        { "instruments" => "Guitar", "confidence" => "high" }
      end

      inferrer.infer(score)
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
