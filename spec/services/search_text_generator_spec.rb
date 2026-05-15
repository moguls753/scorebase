# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchTextGenerator do
  let(:client)    { instance_double(LlmClient) }
  let(:generator) { described_class.new(client: client) }

  describe "#template_for" do
    it "uses RICH_PROMPT when music21 extraction succeeded" do
      score = build(:score, source: "pdmx", extraction_status: :extracted)
      expect(generator.send(:template_for, score)).to eq(described_class::RICH_PROMPT)
    end

    it "uses SPARSE_PROMPT for vision-extracted SMD" do
      score = build(:score, :smd, extraction_status: :vision_extracted)
      expect(generator.send(:template_for, score)).to eq(described_class::SPARSE_PROMPT)
    end

    it "uses SPARSE_PROMPT for unextracted scores (IMSLP, pending CPDL, etc.)" do
      score = build(:score, source: "imslp", extraction_status: :pending)
      expect(generator.send(:template_for, score)).to eq(described_class::SPARSE_PROMPT)
    end
  end

  describe "#build_metadata" do
    it "prefers clean_title when present (strips SMD marketing boilerplate)" do
      score = build(:score, :smd,
                    title: "Good Rockin' Tonight by Elvis Presley Guitar Tab Digital Sheet Music",
                    clean_title: "Good Rockin' Tonight")
      metadata = generator.send(:build_metadata, score)
      expect(metadata[:title]).to eq("Good Rockin' Tonight")
    end

    it "falls back to title when clean_title is blank" do
      score = build(:score, source: "pdmx", title: "Symphony No. 5", clean_title: nil)
      metadata = generator.send(:build_metadata, score)
      expect(metadata[:title]).to eq("Symphony No. 5")
    end
  end
end
