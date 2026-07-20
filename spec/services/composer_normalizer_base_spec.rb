# frozen_string_literal: true

require "rails_helper"

RSpec.describe ComposerNormalizerBase do
  # Concrete test class to test the base behavior
  let(:normalizer_class) do
    Class.new(ComposerNormalizerBase) do
      def provider_name
        "test"
      end

      def request_batch(_batch)
        # Not used in these tests
      end
    end
  end

  let(:normalizer) { normalizer_class.new }

  before do
    ComposerMapping.delete_all
    Score.delete_all
  end

  describe "#apply_api_results" do
    let!(:score) { create(:score, composer: "Smith, John", composer_status: "pending") }

    it "caches and normalizes when AI returns a result" do
      results = [{ "original" => "Smith, John", "normalized" => "Smith, John Francis" }]

      expect { normalizer.send(:apply_api_results, results) }
        .to change { ComposerMapping.count }.by(1)

      expect(ComposerMapping.lookup("Smith, John")).to eq("Smith, John Francis")
      expect(score.reload.composer_status).to eq("normalized")
      expect(score.composer).to eq("Smith, John Francis")
    end

    it "does NOT cache when AI returns nil (allows retry)" do
      results = [{ "original" => "Smith, John", "normalized" => nil }]

      expect { normalizer.send(:apply_api_results, results) }
        .not_to change { ComposerMapping.count }

      expect(ComposerMapping.processed?("Smith, John")).to be false
      expect(score.reload.composer_status).to eq("failed")
      expect(score.composer).to eq("Smith, John") # unchanged
    end

    it "skips results with nil original" do
      results = [{ "original" => nil, "normalized" => "Smith, John Francis" }]

      expect { normalizer.send(:apply_api_results, results) }
        .not_to change { ComposerMapping.count }

      expect(score.reload.composer_status).to eq("pending")
    end
  end

  # update_all skips the before_save that derives composer_search_normalized,
  # which is the column the FTS trigger indexes. Left unhandled, every
  # normalization run silently desynced search from display.
  describe "keeping the search column in sync" do
    it "derives composer_search_normalized when applying an API result" do
      create(:score, composer: "Antonín Dvořák", composer_status: "pending")

      normalizer.send(:apply_api_results,
                      [{ "original" => "Antonín Dvořák", "normalized" => "Dvořák, Antonín" }])

      score = Score.find_by(composer: "Dvořák, Antonín")
      expect(score.composer_search_normalized).to eq("Dvorak, Antonin")
    end

    it "derives composer_search_normalized when applying a cached mapping" do
      create(:score, composer: "Antonín Dvořák", composer_status: "pending")
      ComposerMapping.create!(original_name: "Antonín Dvořák",
                              normalized_name: "Dvořák, Antonín", source: "test")

      normalizer.send(:apply_cached_mappings)

      score = Score.find_by(composer: "Dvořák, Antonín")
      expect(score.composer_search_normalized).to eq("Dvorak, Antonin")
    end
  end
end
