# frozen_string_literal: true

require "rails_helper"

RSpec.describe GenreInferrer do
  let(:client) { instance_double(LlmClient) }
  let(:inferrer) { described_class.new(client: client) }

  describe "#infer" do
    let(:score) { create(:score, title: "Requiem in D minor", composer: "Mozart, Wolfgang Amadeus") }

    it "returns genre from LLM response" do
      allow(client).to receive(:chat_json).and_return({ "genre" => "Requiem", "confidence" => "high" })

      results = inferrer.infer(score)
      result = results.first

      expect(result.genre).to eq("Requiem")
      expect(result.confidence).to eq("high")
      expect(result).to be_success
    end

    it "returns nil for unknown genres not in vocabulary" do
      allow(client).to receive(:chat_json).and_return({ "genre" => "InventedGenre", "confidence" => "low" })

      results = inferrer.infer(score)
      result = results.first

      expect(result.genre).to be_nil
    end

    it "handles null response from LLM" do
      allow(client).to receive(:chat_json).and_return({ "genre" => nil, "confidence" => nil })

      results = inferrer.infer(score)
      result = results.first

      expect(result.genre).to be_nil
      expect(result).to be_success      # API call succeeded
      expect(result).not_to be_found    # But genre was not identified
    end

    it "handles LLM errors gracefully" do
      allow(client).to receive(:chat_json).and_raise(LlmClient::Error, "API down")

      results = inferrer.infer(score)
      result = results.first

      expect(result).not_to be_success
      expect(result.error).to eq("API down")
    end
  end

  describe "GENRES" do
    it "loads vocabulary from YAML" do
      expect(described_class::GENRES).to include("Mass", "Requiem", "Motet", "Sonata", "Fugue")
    end
  end
end
