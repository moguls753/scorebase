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
      expect(Rails.cache.read("hub/ensembles")).to be_an(Array)
    end
  end

  describe ".ensembles" do
    it "includes an allowlisted category meeting the threshold and excludes below-threshold and non-allowlisted values" do
      12.times { create(:score, :smd, smd_category: "Concert Band") }  # allowlisted, >= THRESHOLD
      5.times  { create(:score, :smd, smd_category: "Orchestra") }     # allowlisted, below THRESHOLD
      12.times { create(:score, :smd, smd_category: "Piano Solo") }    # not allowlisted (a format), huge

      names = described_class.ensembles.map { |e| e[:name] }

      expect(names).to include("Concert Band")
      expect(names).not_to include("Orchestra")   # below threshold
      expect(names).not_to include("Piano Solo")  # not in allowlist
    end

    it "counts only deduplicated arrangements (reps + ungrouped), not hidden members" do
      create(:score, :smd, smd_category: "Concert Band", group_key: "g", is_group_representative: true)
      # hidden members of the same arrangement must not inflate the count
      3.times { create(:score, :smd, smd_category: "Concert Band", group_key: "g", is_group_representative: false) }
      11.times { create(:score, :smd, smd_category: "Concert Band") } # ungrouped reps

      concert_band = described_class.ensembles.find { |e| e[:name] == "Concert Band" }

      expect(concert_band[:count]).to eq(12) # 1 rep + 11 ungrouped, members excluded
      expect(concert_band[:slug]).to eq("concert-band")
    end
  end

  describe ".ensemble_groups" do
    it "buckets threshold-meeting categories into instrumental and choral groups" do
      12.times { create(:score, :smd, smd_category: "Concert Band") }
      12.times { create(:score, :smd, smd_category: "SATB Choir") }

      groups = described_class.ensemble_groups

      expect(groups[:instrumental].map { |e| e[:name] }).to include("Concert Band")
      expect(groups[:instrumental].map { |e| e[:name] }).not_to include("SATB Choir")
      expect(groups[:choral].map { |e| e[:name] }).to include("SATB Choir")
      expect(groups[:choral].map { |e| e[:name] }).not_to include("Concert Band")
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

    it "resolves an ensemble slug to its exact smd_category name" do
      12.times { create(:score, :smd, smd_category: "Concert Band") }

      expect(described_class.find_by_slug(:ensembles, "concert-band")).to eq("Concert Band")
    end

    it "returns nil for a bogus ensemble slug" do
      expect(described_class.find_by_slug(:ensembles, "nonexistent")).to be_nil
    end

    it "gates an ensemble on the deduped rep count, not part-inflated rows" do
      # 5 reps (< THRESHOLD) + 6 hidden members of one arrangement. Without
      # deduplicate_arrangements the 11 rows would wrongly qualify the category.
      5.times { create(:score, :smd, smd_category: "Concert Band") }
      6.times { create(:score, :smd, smd_category: "Concert Band", group_key: "g", is_group_representative: false) }

      expect(described_class.find_by_slug(:ensembles, "concert-band")).to be_nil
    end

    it "re-gates a cached ensemble via current_count's deduped live count" do
      reps = 12.times.map { create(:score, :smd, smd_category: "Concert Band") }
      Rails.cache.delete("hub/ensembles")
      expect(described_class.ensembles.find { |e| e[:slug] == "concert-band" }).to be_present

      # 5 reps + 6 members: raw rows (11) still >= THRESHOLD, deduped (5) < THRESHOLD.
      # current_count must recount deduped -> nil despite the stale cache listing it.
      reps.last(7).each(&:destroy)
      6.times { create(:score, :smd, smd_category: "Concert Band", group_key: "g", is_group_representative: false) }

      expect(described_class.find_by_slug(:ensembles, "concert-band")).to be_nil
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
