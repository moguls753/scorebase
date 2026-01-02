# frozen_string_literal: true

require "rails_helper"

RSpec.describe InstrumentInferrer do
  let(:client) { instance_double(LlmClient) }
  let(:inferrer) { described_class.new(client: client) }
  let(:score) { create(:score, title: "Piano Sonata No. 14", composer: "Beethoven, Ludwig van", period: "Classical") }

  describe "#infer" do
    context "with single score" do
      it "returns instruments from LLM response" do
        allow(client).to receive(:chat_json).and_return({ "instruments" => "Piano", "confidence" => "high" })

        results = inferrer.infer(score)

        expect(results.first.instruments).to eq("Piano")
        expect(results.first).to be_found
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
    end

    context "with multiple scores" do
      let(:score2) { create(:score, title: "Guitar Etude", composer: "Sor, Fernando", period: "Classical") }

      it "returns results for each score" do
        allow(client).to receive(:chat_json).and_return({
          "results" => [
            { "id" => 1, "instruments" => "Piano", "confidence" => "high" },
            { "id" => 2, "instruments" => "Guitar", "confidence" => "high" }
          ]
        })

        results = inferrer.infer([score, score2])

        expect(results.length).to eq(2)
        expect(results[0].instruments).to eq("Piano")
        expect(results[1].instruments).to eq("Guitar")
      end

      it "handles batch errors gracefully" do
        allow(client).to receive(:chat_json).and_raise(LlmClient::Error, "API down")

        results = inferrer.infer([score, score2])

        expect(results.length).to eq(2)
        expect(results.all? { |r| !r.success? }).to be true
      end
    end

    context "with empty input" do
      it "returns empty array" do
        results = inferrer.infer([])
        expect(results).to eq([])
      end
    end
  end
end
