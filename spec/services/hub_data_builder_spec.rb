# frozen_string_literal: true

require "rails_helper"

RSpec.describe HubDataBuilder do
  let(:memory_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(memory_store)
  end

  describe ".warm_all" do
    it "caches all hub data types" do
      described_class.warm_all

      expect(Rails.cache.read("hub/composers")).to be_an(Array)
      expect(Rails.cache.read("hub/genres")).to be_an(Array)
      expect(Rails.cache.read("hub/instruments")).to be_an(Array)
      expect(Rails.cache.read("hub/periods")).to be_an(Array)
    end
  end

  describe ".genres" do
    it "returns items with correct structure" do
      12.times { create(:score, genres: "Sacred") }

      genres = described_class.genres

      expect(genres.first).to include(:name, :slug, :count)
    end

    it "only includes items meeting threshold" do
      5.times { create(:score, genres: "Rare") }
      12.times { create(:score, genres: "Common") }

      genres = described_class.genres

      expect(genres.map { |g| g[:name] }).to include("Common")
      expect(genres.map { |g| g[:name] }).not_to include("Rare")
    end
  end

  describe ".periods" do
    it "only includes items meeting threshold" do
      5.times { create(:score, genres: "Baroque") }
      12.times { create(:score, genres: "Romantic") }

      periods = described_class.periods

      expect(periods.map { |p| p[:name] }).to include("Romantic")
      expect(periods.map { |p| p[:name] }).not_to include("Baroque")
    end

    it "uses case-sensitive matching" do
      # lowercase "classical" is PDMX pop tag, not Classical period
      12.times { create(:score, genres: "classical") }
      12.times { create(:score, genres: "Classical") }

      periods = described_class.periods
      classical = periods.find { |p| p[:name] == "Classical" }

      # Should only count capitalized "Classical", not lowercase
      expect(classical[:count]).to eq(12)
    end
  end

  describe ".find_by_slug" do
    it "returns the name for a valid slug" do
      12.times { create(:score, genres: "Sacred") }

      expect(described_class.find_by_slug(:genres, "sacred")).to eq("Sacred")
    end

    it "returns nil for invalid slug" do
      expect(described_class.find_by_slug(:genres, "nonexistent")).to be_nil
    end
  end
end
