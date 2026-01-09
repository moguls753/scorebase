# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScoreMetricsCalculator do
  describe "#throughput" do
    it "calculates events per second" do
      score = build(:score, event_count: 600, duration_seconds: 120.0)
      expect(described_class.new(score).throughput).to eq(5.0)
    end

    it "uses estimated_duration as fallback" do
      score = build(:score, event_count: 600, duration_seconds: nil, estimated_duration_seconds: 100.0)
      expect(described_class.new(score).throughput).to eq(6.0)
    end

    it "returns nil when missing data" do
      score = build(:score, event_count: nil, duration_seconds: 120.0)
      expect(described_class.new(score).throughput).to be_nil
    end
  end

  describe "#note_density" do
    it "calculates events per measure" do
      score = build(:score, event_count: 400, measure_count: 20)
      expect(described_class.new(score).note_density).to eq(20.0)
    end
  end

  describe "#harmonic_rhythm" do
    it "calculates chords per measure" do
      score = build(:score, chord_count: 80, measure_count: 20)
      expect(described_class.new(score).harmonic_rhythm).to eq(4.0)
    end
  end
end
