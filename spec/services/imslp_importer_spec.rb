# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImslpImporter do
  let(:importer) { described_class.new }

  before do
    ComposerMapping.delete_all
  end

  describe "#normalize_composer" do
    it "returns nil for blank input" do
      expect(importer.send(:normalize_composer, nil)).to be_nil
      expect(importer.send(:normalize_composer, "")).to be_nil
    end

    it "returns cached value from ComposerMapping" do
      ComposerMapping.create!(original_name: "Bach", normalized_name: "Bach, Johann Sebastian", source: "test")
      expect(importer.send(:normalize_composer, "Bach")).to eq("Bach, Johann Sebastian")
    end

    it "registers priority composers immediately" do
      result = importer.send(:normalize_composer, "Bach, Johann Sebastian")
      expect(result).to eq("Bach, Johann Sebastian")
      expect(ComposerMapping.exists?(original_name: "Bach, Johann Sebastian")).to be true
    end

    it "returns original for unknown composers" do
      result = importer.send(:normalize_composer, "Unknown Composer")
      expect(result).to eq("Unknown Composer")
    end
  end

  describe "#normalize_composers_batch!" do
    it "delegates to ComposerNormalizer" do
      normalizer = instance_double(ComposerNormalizer)
      allow(ComposerNormalizer).to receive(:new).and_return(normalizer)
      allow(normalizer).to receive(:normalize!)

      importer.send(:normalize_composers_batch!)

      expect(ComposerNormalizer).to have_received(:new)
      expect(normalizer).to have_received(:normalize!)
    end
  end
end
