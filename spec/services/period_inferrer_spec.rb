# frozen_string_literal: true

require "rails_helper"

RSpec.describe PeriodInferrer do
  describe ".infer" do
    it "returns Baroque for Bach" do
      expect(described_class.infer("Bach, Johann Sebastian")).to eq("Baroque")
    end

    it "returns Renaissance for Palestrina" do
      expect(described_class.infer("Palestrina, Giovanni Pierluigi da")).to eq("Renaissance")
    end

    it "returns Romantic for Chopin" do
      expect(described_class.infer("Chopin, Frédéric")).to eq("Romantic")
    end

    it "returns nil for unknown composer" do
      expect(described_class.infer("Unknown, Joe")).to be_nil
    end

    it "returns nil for blank composer" do
      expect(described_class.infer("")).to be_nil
      expect(described_class.infer(nil)).to be_nil
    end
  end

  describe "COMPOSER_PERIODS" do
    it "loads from YAML" do
      expect(described_class::COMPOSER_PERIODS).to be_a(Hash)
      expect(described_class::COMPOSER_PERIODS.size).to be > 50
    end

    it "includes major periods" do
      periods = described_class::COMPOSER_PERIODS.values.uniq
      expect(periods).to include("Medieval", "Renaissance", "Baroque", "Classical", "Romantic")
    end
  end
end
