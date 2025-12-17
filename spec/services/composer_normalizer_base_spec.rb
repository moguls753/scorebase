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
    let!(:score) { create(:score, composer: "Smith, John", normalization_status: "pending") }
    let(:batch) { [["Smith, John", "Sonata", nil, nil, nil]] }

    it "caches and normalizes when AI returns a result" do
      results = [{ "index" => 0, "normalized" => "Smith, John Francis" }]

      expect { normalizer.send(:apply_api_results, results, batch) }
        .to change { ComposerMapping.count }.by(1)

      expect(ComposerMapping.lookup("Smith, John")).to eq("Smith, John Francis")
      expect(score.reload.normalization_status).to eq("normalized")
      expect(score.composer).to eq("Smith, John Francis")
    end

    it "does NOT cache when AI returns nil (allows retry)" do
      results = [{ "index" => 0, "normalized" => nil }]

      expect { normalizer.send(:apply_api_results, results, batch) }
        .not_to change { ComposerMapping.count }

      expect(ComposerMapping.processed?("Smith, John")).to be false
      expect(score.reload.normalization_status).to eq("failed")
      expect(score.composer).to eq("Smith, John") # unchanged
    end

    it "handles string index from AI" do
      results = [{ "index" => "0", "normalized" => "Smith, John Francis" }]

      expect { normalizer.send(:apply_api_results, results, batch) }
        .to change { ComposerMapping.count }.by(1)

      expect(score.reload.normalization_status).to eq("normalized")
    end

    it "skips invalid index" do
      results = [{ "index" => 99, "normalized" => "Smith, John Francis" }]

      expect { normalizer.send(:apply_api_results, results, batch) }
        .not_to change { ComposerMapping.count }

      expect(score.reload.normalization_status).to eq("pending")
    end
  end
end
