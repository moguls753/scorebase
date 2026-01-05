# frozen_string_literal: true

require "rails_helper"

RSpec.describe VocalDetector do
  let(:client) { instance_double(LlmClient) }
  let(:detector) { described_class.new(client: client) }
  let(:score) { create(:score, title: "Ave Maria", part_names: "Soprano, Alto, Tenor, Bass") }

  describe "#detect" do
    context "with single score" do
      it "returns has_vocal from LLM response" do
        allow(client).to receive(:chat_json).and_return({ "has_vocal" => true, "confidence" => "high" })

        results = detector.detect(score)

        expect(results.first.has_vocal).to be true
        expect(results.first.confidence).to eq("high")
        expect(results.first).to be_success
      end

      it "includes part names in prompt" do
        score = create(:score, title: "Test", part_names: "Alto Saxophone, Piano")

        expect(client).to receive(:chat_json) do |prompt|
          expect(prompt).to include("Part Names: Alto Saxophone, Piano")
          { "has_vocal" => false, "confidence" => "high" }
        end

        detector.detect(score)
      end

      it "includes has_extracted_lyrics in prompt" do
        score = create(:score, title: "Test", has_extracted_lyrics: true)

        expect(client).to receive(:chat_json) do |prompt|
          expect(prompt).to include("Has Extracted Lyrics: true")
          { "has_vocal" => true, "confidence" => "high" }
        end

        detector.detect(score)
      end

      it "handles errors gracefully" do
        allow(client).to receive(:chat_json).and_raise(LlmClient::Error, "API down")

        results = detector.detect(score)

        expect(results.first).not_to be_success
        expect(results.first.error).to eq("API down")
      end
    end

    context "with multiple scores" do
      let(:score2) { create(:score, title: "Piano Sonata", part_names: "Piano") }

      it "returns results for each score" do
        allow(client).to receive(:chat_json).and_return({
          "results" => [
            { "id" => 1, "has_vocal" => true, "confidence" => "high" },
            { "id" => 2, "has_vocal" => false, "confidence" => "high" }
          ]
        })

        results = detector.detect([score, score2])

        expect(results.length).to eq(2)
        expect(results[0].has_vocal).to be true
        expect(results[1].has_vocal).to be false
      end

      it "handles batch errors gracefully" do
        allow(client).to receive(:chat_json).and_raise(LlmClient::Error, "API down")

        results = detector.detect([score, score2])

        expect(results.length).to eq(2)
        expect(results.all? { |r| !r.success? }).to be true
      end
    end

    context "with empty input" do
      it "returns empty array" do
        results = detector.detect([])
        expect(results).to eq([])
      end
    end
  end
end
