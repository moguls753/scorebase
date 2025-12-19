# frozen_string_literal: true

require "rails_helper"

RSpec.describe ComposerMapping do
  before { ComposerMapping.delete_all }

  describe ".known_unnormalizable?" do
    it "matches anonymous patterns" do
      expect(described_class.known_unnormalizable?("Anonymous")).to be true
      expect(described_class.known_unnormalizable?("Anon.")).to be true
      expect(described_class.known_unnormalizable?("anónimo")).to be true
      expect(described_class.known_unnormalizable?("(Anonim)")).to be true
      expect(described_class.known_unnormalizable?("ANONIMO")).to be true
    end

    it "matches unknown patterns strictly" do
      expect(described_class.known_unnormalizable?("Unknown")).to be true
      expect(described_class.known_unnormalizable?("(unknown)")).to be true
      expect(described_class.known_unnormalizable?("Unknown.")).to be true
      expect(described_class.known_unnormalizable?("unknown composer")).to be true
      expect(described_class.known_unnormalizable?("Unknown artist")).to be true
      expect(described_class.known_unnormalizable?("Composer: Unknown")).to be true
      expect(described_class.known_unnormalizable?("Music: unknown")).to be true
    end

    it "does NOT match unknown when part of real composer name" do
      # These have extractable real composers - should go to API
      expect(described_class.known_unnormalizable?("Dowland, Unknown")).to be false
      expect(described_class.known_unnormalizable?("Barnby, Unknown")).to be false
      expect(described_class.known_unnormalizable?("Gesualdo, Unknown")).to be false
      expect(described_class.known_unnormalizable?("Unknown & Tchaikovsky")).to be false
      expect(described_class.known_unnormalizable?("Johann Pachelbel (1653-1706)Arr: Unknown")).to be false
    end

    it "does NOT match band names containing unknown" do
      expect(described_class.known_unnormalizable?("Unknown Mortal Orchestra")).to be false
    end

    it "matches traditional/folk/various" do
      expect(described_class.known_unnormalizable?("Traditional")).to be true
      expect(described_class.known_unnormalizable?("Traditional Celtic")).to be true
      expect(described_class.known_unnormalizable?("Folk Song")).to be true
      expect(described_class.known_unnormalizable?("Nigerian Folk Song")).to be true
      expect(described_class.known_unnormalizable?("Various Artists")).to be true
      expect(described_class.known_unnormalizable?("Various")).to be true
    end
  end

  describe ".looks_like_name?" do
    it "accepts valid composer names" do
      expect(described_class.looks_like_name?("Bach, Johann Sebastian")).to be true
      expect(described_class.looks_like_name?("J.S. Bach")).to be true
      expect(described_class.looks_like_name?("Dvořák, Antonín")).to be true
      expect(described_class.looks_like_name?("Fauré, Gabriel")).to be true
      expect(described_class.looks_like_name?("Dowland, Unknown")).to be true # name-like format
    end

    it "rejects garbage strings" do
      expect(described_class.looks_like_name?("'A Retreat & Country Dance'")).to be false
      expect(described_class.looks_like_name?("http://example.com")).to be false
      expect(described_class.looks_like_name?("Arr. by Someone (2020)")).to be false
      expect(described_class.looks_like_name?("BWV 509")).to be false
    end

    it "rejects strings that are too long" do
      long_string = "A" * 51
      expect(described_class.looks_like_name?(long_string)).to be false
    end

    it "rejects strings with too many words" do
      expect(described_class.looks_like_name?("One Two Three Four Five Six")).to be false
    end
  end

  describe ".cacheable?" do
    context "cacheable cases" do
      it "caches real composer names" do
        expect(described_class.cacheable?("Bach, Johann Sebastian")).to be true
        expect(described_class.cacheable?("J.S. Bach")).to be true
        expect(described_class.cacheable?("Dvořák, Antonín")).to be true
      end

      it "caches unnormalizable patterns (stored with nil)" do
        expect(described_class.cacheable?("Anonymous")).to be true
        expect(described_class.cacheable?("Traditional")).to be true
        expect(described_class.cacheable?("Folk Song")).to be true
      end

      it "caches 'Dowland, Unknown' (name-like, will go to API)" do
        # This is a key case: looks like a name, not unnormalizable, should be cached
        expect(described_class.cacheable?("Dowland, Unknown")).to be true
      end
    end

    context "non-cacheable cases (garbage)" do
      it "does not cache garbage strings" do
        expect(described_class.cacheable?("'A Retreat & Country Dance'")).to be false
        expect(described_class.cacheable?("Vivaldi (1678) arr. someone")).to be false
        expect(described_class.cacheable?("http://example.com/score")).to be false
      end

      it "does not cache garbage even if AI could extract composer from context" do
        # AI might use title/editor to find composer, but we don't cache garbage originals
        expect(described_class.cacheable?("garbage123xyz")).to be false
      end
    end
  end

  describe ".register" do
    it "stores cacheable mappings with normalized name" do
      mapping = described_class.register(original: "J.S. Bach", normalized: "Bach, Johann Sebastian", source: "groq")
      expect(mapping.normalized_name).to eq("Bach, Johann Sebastian")
      expect(mapping.source).to eq("groq")
    end

    it "stores unnormalizable patterns with nil" do
      mapping = described_class.register(original: "Anonymous", normalized: nil, source: "pattern")
      expect(mapping).to be_present
      expect(mapping.normalized_name).to be_nil
      expect(mapping.source).to eq("pattern")
    end

    it "can store nil for name-like strings (model allows it)" do
      # Model allows caching nil - but normalizer should NOT cache AI failures.
      # Only pattern-matched nils (Anonymous, Traditional) should be cached.
      # This test verifies the model capability, not the recommended usage.
      mapping = described_class.register(original: "Smith, John", normalized: nil, source: "groq")
      expect(mapping).to be_present
      expect(mapping.normalized_name).to be_nil
    end

    it "skips garbage even with valid normalized result from AI" do
      # AI used title/editor context to find composer, but don't cache garbage → composer mapping
      mapping = described_class.register(original: "'Garbage String'", normalized: "Mozart, Wolfgang Amadeus", source: "groq")
      expect(mapping).to be_nil
      expect(described_class.processed?("'Garbage String'")).to be false
    end

    it "is idempotent - doesn't duplicate on second call" do
      described_class.register(original: "Bach", normalized: "Bach, Johann Sebastian", source: "test")
      described_class.register(original: "Bach", normalized: "Bach, Johann Sebastian", source: "test")
      expect(described_class.where(original_name: "Bach").count).to eq(1)
    end
  end

  describe ".processed?" do
    it "returns true if mapping exists with normalized name" do
      described_class.register(original: "Bach", normalized: "Bach, Johann Sebastian", source: "test")
      expect(described_class.processed?("Bach")).to be true
    end

    it "returns true if mapping exists with nil (failed lookup)" do
      described_class.register(original: "Anonymous", normalized: nil, source: "pattern")
      expect(described_class.processed?("Anonymous")).to be true
    end

    it "returns false if mapping does not exist" do
      expect(described_class.processed?("Never Seen Before")).to be false
    end
  end

  describe ".lookup" do
    it "returns normalized name if found" do
      described_class.register(original: "Bach", normalized: "Bach, Johann Sebastian", source: "test")
      expect(described_class.lookup("Bach")).to eq("Bach, Johann Sebastian")
    end

    it "returns nil if not found in cache" do
      expect(described_class.lookup("Nonexistent")).to be_nil
    end

    it "returns nil if cached as nil (unnormalizable or failed)" do
      described_class.register(original: "Anonymous", normalized: nil, source: "pattern")
      expect(described_class.lookup("Anonymous")).to be_nil
    end
  end

  describe "integration: the three types of originals" do
    it "handles unnormalizable pattern correctly" do
      original = "Traditional Folk Song"

      # It's unnormalizable
      expect(described_class.known_unnormalizable?(original)).to be true
      # But it IS cacheable (we cache the nil)
      expect(described_class.cacheable?(original)).to be true

      # Register with nil
      described_class.register(original: original, normalized: nil, source: "pattern")

      # Now it's processed
      expect(described_class.processed?(original)).to be true
      # Lookup returns nil
      expect(described_class.lookup(original)).to be_nil
    end

    it "handles name-like original correctly" do
      original = "J.S. Bach"

      # Not unnormalizable
      expect(described_class.known_unnormalizable?(original)).to be false
      # Is cacheable
      expect(described_class.cacheable?(original)).to be true

      # Register with normalized result
      described_class.register(original: original, normalized: "Bach, Johann Sebastian", source: "groq")

      # Now it's processed
      expect(described_class.processed?(original)).to be true
      # Lookup returns normalized name
      expect(described_class.lookup(original)).to eq("Bach, Johann Sebastian")
    end

    it "handles garbage original correctly" do
      original = "'Some Garbage (2020) arr. xyz'"

      # Not unnormalizable
      expect(described_class.known_unnormalizable?(original)).to be false
      # NOT cacheable
      expect(described_class.cacheable?(original)).to be false

      # Try to register - should be rejected
      mapping = described_class.register(original: original, normalized: "Mozart, Wolfgang Amadeus", source: "groq")
      expect(mapping).to be_nil

      # Not processed (not in cache)
      expect(described_class.processed?(original)).to be false
    end
  end
end
