# frozen_string_literal: true

require "rails_helper"

RSpec.describe ComposerMapping do
  before { ComposerMapping.delete_all }

  describe ".known_unnormalizable?" do
    it "matches anonymous, traditional, and folk patterns" do
      expect(described_class.known_unnormalizable?("Anonymous")).to be true
      expect(described_class.known_unnormalizable?("anónimo")).to be true
      expect(described_class.known_unnormalizable?("Traditional Celtic")).to be true
      expect(described_class.known_unnormalizable?("Folk Song")).to be true
      expect(described_class.known_unnormalizable?("Various")).to be true
    end

    it "matches standalone unknown but not as part of real names" do
      expect(described_class.known_unnormalizable?("Unknown")).to be true
      expect(described_class.known_unnormalizable?("unknown composer")).to be true

      expect(described_class.known_unnormalizable?("Dowland, Unknown")).to be false
      expect(described_class.known_unnormalizable?("Unknown Mortal Orchestra")).to be false
    end
  end

  describe ".looks_like_name?" do
    it "accepts valid composer names" do
      expect(described_class.looks_like_name?("Bach, Johann Sebastian")).to be true
      expect(described_class.looks_like_name?("Dvořák, Antonín")).to be true
    end

    it "rejects garbage strings" do
      expect(described_class.looks_like_name?("http://example.com")).to be false
      expect(described_class.looks_like_name?("BWV 509")).to be false
      expect(described_class.looks_like_name?("A" * 51)).to be false
      expect(described_class.looks_like_name?("One Two Three Four Five Six")).to be false
    end
  end

  describe ".cacheable?" do
    it "caches real names and unnormalizable patterns, rejects garbage" do
      expect(described_class.cacheable?("Bach, Johann Sebastian")).to be true
      expect(described_class.cacheable?("Anonymous")).to be true
      expect(described_class.cacheable?("'A Retreat & Country Dance'")).to be false
    end
  end

  describe ".register" do
    it "stores and retrieves normalized mappings" do
      described_class.register(original: "J.S. Bach", normalized: "Bach, Johann Sebastian", source: "groq")

      expect(described_class.processed?("J.S. Bach")).to be true
      expect(described_class.lookup("J.S. Bach")).to eq("Bach, Johann Sebastian")
    end

    it "stores unnormalizable patterns with nil" do
      described_class.register(original: "Anonymous", normalized: nil, source: "pattern")

      expect(described_class.processed?("Anonymous")).to be true
      expect(described_class.lookup("Anonymous")).to be_nil
    end

    it "skips garbage originals" do
      mapping = described_class.register(original: "'Garbage String'", normalized: "Mozart, Wolfgang Amadeus", source: "groq")

      expect(mapping).to be_nil
      expect(described_class.processed?("'Garbage String'")).to be false
    end

    it "is idempotent" do
      described_class.register(original: "Bach", normalized: "Bach, Johann Sebastian", source: "test")
      described_class.register(original: "Bach", normalized: "Bach, Johann Sebastian", source: "test")
      expect(described_class.where(original_name: "Bach").count).to eq(1)
    end
  end

  describe ".lookup" do
    it "returns nil for unknown entries" do
      expect(described_class.lookup("Nonexistent")).to be_nil
    end
  end
end
