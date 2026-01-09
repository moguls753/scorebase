# frozen_string_literal: true

require "rails_helper"

RSpec.describe TempoEstimator do
  describe ".estimate" do
    # Representative samples from each language
    it "estimates Italian tempo terms" do
      expect(described_class.estimate("Adagio")).to eq(70)
      expect(described_class.estimate("Allegro")).to eq(130)
      expect(described_class.estimate("Presto")).to eq(170)
    end

    it "estimates German tempo terms" do
      expect(described_class.estimate("Langsam")).to eq(50)
      expect(described_class.estimate("Schnell")).to eq(150)
    end

    it "estimates French tempo terms" do
      expect(described_class.estimate("Lent")).to eq(50)
      expect(described_class.estimate("Modéré")).to eq(110)
    end

    it "extracts base tempo from compound markings" do
      expect(described_class.estimate("Allegro ma non troppo")).to eq(130)
      expect(described_class.estimate("Andante con moto")).to eq(90)
    end

    it "is case insensitive" do
      expect(described_class.estimate("ALLEGRO")).to eq(130)
      expect(described_class.estimate("allegro")).to eq(130)
    end

    it "returns nil for unrecognized text" do
      expect(described_class.estimate("Unknown")).to be_nil
      expect(described_class.estimate("")).to be_nil
      expect(described_class.estimate(nil)).to be_nil
    end

    # Critical: longer forms must match before shorter ones
    context "pattern ordering" do
      it "matches Larghetto (60) before Largo (50)" do
        expect(described_class.estimate("Larghetto")).to eq(60)
      end

      it "matches Prestissimo (190) before Presto (170)" do
        expect(described_class.estimate("Prestissimo")).to eq(190)
      end

      it "matches Sehr schnell (170) before Schnell (150)" do
        expect(described_class.estimate("Sehr schnell")).to eq(170)
      end
    end
  end

  describe ".recognizes?" do
    it "returns true for known terms, false otherwise" do
      expect(described_class.recognizes?("Allegro")).to be true
      expect(described_class.recognizes?("Unknown")).to be false
    end
  end
end
