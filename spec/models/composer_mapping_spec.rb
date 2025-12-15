# frozen_string_literal: true

require "rails_helper"

RSpec.describe ComposerMapping do
  before { ComposerMapping.delete_all }

  describe ".cacheable?" do
    it "caches real names" do
      expect(described_class.cacheable?("Bach, Johann Sebastian")).to be true
      expect(described_class.cacheable?("J.S. Bach")).to be true
    end

    it "caches known uncacheable patterns (as nil)" do
      expect(described_class.cacheable?("Anonymous")).to be true
      expect(described_class.cacheable?("Traditional")).to be true
    end

    it "does not cache garbage" do
      expect(described_class.cacheable?("'A Retreat & Country Dance'")).to be false
      expect(described_class.cacheable?("Vivaldi (1678) arr. someone")).to be false
    end
  end

  describe ".register" do
    it "stores cacheable mappings" do
      mapping = described_class.register(original: "J.S. Bach", normalized: "Bach, Johann Sebastian", source: "test")
      expect(mapping.normalized_name).to eq("Bach, Johann Sebastian")
    end

    it "skips garbage even with valid normalized result" do
      mapping = described_class.register(original: "'Garbage'", normalized: "Mozart, Wolfgang Amadeus", source: "test")
      expect(mapping).to be_nil
    end
  end
end
