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

  describe "#fetch_composer_works" do
    it "follows IMSLP's legacy query-continue pagination across pages" do
      page1 = {
        "query" => { "categorymembers" => [
          { "pageid" => 1, "title" => "Work A (Bach, Johann Sebastian)" }
        ] },
        "query-continue" => { "categorymembers" => { "cmcontinue" => "TOKEN-2" } }
      }
      page2 = {
        "query" => { "categorymembers" => [
          { "pageid" => 2, "title" => "Work B (Bach, Johann Sebastian)" }
        ] }
      }
      allow(importer).to receive(:api_request).and_return(page1, page2)

      works = importer.send(:fetch_composer_works, "Bach,_Johann_Sebastian")

      expect(works.map { |w| w.dig("intvals", "pageid") }).to eq([1, 2])
    end
  end

  describe "#process_work quality gate" do
    it "skips a work that yields no downloadable file" do
      details = {
        "wikitext" => { "*" => "|Work Title=Empty Work\n|Instrumentation=Piano" },
        "categories" => []
      }
      allow(importer).to receive(:fetch_work_details).and_return(details)
      work = {
        "intvals" => { "pageid" => 99, "composer" => "Bach, Johann Sebastian",
                       "worktitle" => "Empty Work" },
        "permlink" => "https://imslp.org/wiki/Empty_Work_(Bach,_Johann_Sebastian)"
      }

      expect { importer.send(:process_work, work) }.not_to change(Score, :count)
    end
  end

  describe "#import_priority! resume" do
    it "skips composers already recorded as done and advances the cursor" do
      allow(Rails.cache).to receive(:read).and_return(ImslpImporter::PRIORITY_COMPOSERS.size - 1)
      allow(Rails.cache).to receive(:write)
      allow(importer).to receive(:fetch_composer_works).and_return([])

      importer.import_priority!

      expect(importer).to have_received(:fetch_composer_works)
        .with(ImslpImporter::PRIORITY_COMPOSERS.last).once
      expect(Rails.cache).to have_received(:write)
        .with(ImslpImporter::PRIORITY_PROGRESS_KEY, ImslpImporter::PRIORITY_COMPOSERS.size, anything)
    end
  end

  describe "#process_batch error handling" do
    it "re-raises RateLimitError so a rate-limit aborts the crawl" do
      allow(importer).to receive(:process_work).and_raise(ImslpImporter::RateLimitError, "403")
      expect {
        importer.send(:process_batch, [{ "intvals" => { "pageid" => 1 } }])
      }.to raise_error(ImslpImporter::RateLimitError)
    end

    it "still swallows a generic per-work error and keeps going" do
      allow(importer).to receive(:process_work).and_raise(StandardError, "boom")
      expect {
        importer.send(:process_batch, [{ "intvals" => { "pageid" => 1 } }])
      }.not_to raise_error
    end
  end
end
