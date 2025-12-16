# frozen_string_literal: true

require "rails_helper"

RSpec.describe HubCacheWarmJob, type: :job do
  let(:memory_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(memory_store)
  end

  describe "#perform" do
    it "caches all hub data types" do
      described_class.new.perform

      expect(Rails.cache.read("hub/genres")).to be_an(Array)
      expect(Rails.cache.read("hub/instruments")).to be_an(Array)
      expect(Rails.cache.read("hub/composers")).to be_an(Array)
      expect(Rails.cache.read("hub/voicings")).to be_an(Array)
    end

    it "caches items with correct structure" do
      12.times { create(:score, genres: "Sacred", voicing: "SATB") }

      described_class.new.perform

      genres = Rails.cache.read("hub/genres")
      expect(genres.first).to include(:name, :slug, :count)
    end

    it "only includes items meeting threshold" do
      5.times { create(:score, voicing: "SATB") }
      12.times { create(:score, voicing: "SAB") }

      described_class.new.perform

      voicings = Rails.cache.read("hub/voicings")
      expect(voicings.map { |v| v[:name] }).to include("SAB")
      expect(voicings.map { |v| v[:name] }).not_to include("SATB")
    end
  end
end
