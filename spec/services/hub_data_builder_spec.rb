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
      # Genres require normalized status and must be in VALID_GENRES allowlist
      12.times { create(:score, genre: "Mass", genre_status: "normalized") }

      genres = described_class.genres

      expect(genres.first).to include(:name, :slug, :count)
    end

    it "only includes items meeting threshold from allowlist" do
      # "Mass" and "Hymn" are in VALID_GENRES, "Rarestuff" is not
      5.times { create(:score, genre: "Mass", genre_status: "normalized") }
      12.times { create(:score, genre: "Hymn", genre_status: "normalized") }
      12.times { create(:score, genre: "Rarestuff", genre_status: "normalized") }

      genres = described_class.genres

      expect(genres.map { |g| g[:name] }).to include("Hymn")
      expect(genres.map { |g| g[:name] }).not_to include("Mass") # below threshold
      expect(genres.map { |g| g[:name] }).not_to include("Rarestuff") # not in allowlist
    end
  end

  describe ".periods" do
    it "only includes items meeting threshold" do
      # Periods now use the period field, not genre
      5.times { create(:score, period: "Baroque") }
      12.times { create(:score, period: "Romantic") }

      periods = described_class.periods

      expect(periods.map { |p| p[:name] }).to include("Romantic")
      expect(periods.map { |p| p[:name] }).not_to include("Baroque")
    end

    it "maps period variants to canonical names" do
      # "Contemporary" should be counted under "Modern"
      12.times { create(:score, period: "Contemporary") }

      periods = described_class.periods
      modern = periods.find { |p| p[:name] == "Modern" }

      expect(modern[:count]).to eq(12)
    end
  end

  describe ".find_by_slug" do
    it "returns the name for a valid slug" do
      12.times { create(:score, genre: "Mass", genre_status: "normalized") }

      expect(described_class.find_by_slug(:genres, "mass")).to eq("Mass")
    end

    it "returns nil for invalid slug" do
      expect(described_class.find_by_slug(:genres, "nonexistent")).to be_nil
    end

    it "returns nil when cached item no longer meets threshold (stale cache)" do
      # Create scores to meet threshold - use valid genre from allowlist
      scores = 12.times.map { create(:score, genre: "Hymn", genre_status: "normalized") }

      # Warm cache - will include Hymn with count 12
      Rails.cache.delete("hub/genres")
      genres = described_class.genres
      expect(genres.find { |g| g[:slug] == "hymn" }).to be_present

      # Delete scores - cache is now stale
      scores.each(&:destroy)

      # Should return nil despite being in cache
      expect(described_class.find_by_slug(:genres, "hymn")).to be_nil
    end
  end
end
