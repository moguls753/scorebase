# frozen_string_literal: true

require "rails_helper"

RSpec.describe CpdlRecoveryJob do
  let(:job) { described_class.new }

  describe "#scope" do
    before do
      Score.delete_all
      # Eligible: empty everything, has external_url
      Score.create!(source: "cpdl", external_id: "1", title: "A",
                    external_url: "https://www.cpdl.org/wiki/index.php/A_(X)")
      # Not eligible: has mxl_path
      Score.create!(source: "cpdl", external_id: "2", title: "B",
                    external_url: "https://www.cpdl.org/wiki/index.php/B_(X)",
                    mxl_path: "https://x/file.mxl")
      # Not eligible: has voicing
      Score.create!(source: "cpdl", external_id: "3", title: "C",
                    external_url: "https://www.cpdl.org/wiki/index.php/C_(X)",
                    voicing: "SATB")
      # Not eligible: not cpdl
      Score.create!(source: "imslp", external_id: "4", title: "D",
                    external_url: "https://imslp.org/wiki/D")
      # Not eligible: no external_url
      Score.create!(source: "cpdl", external_id: "5", title: "E")
    end

    it "selects only cpdl rows that are entirely empty and have an external_url" do
      ids = job.send(:scope).pluck(:external_id)
      expect(ids).to contain_exactly("1")
    end

    it "honors shard slicing by id" do
      scope_shard0 = job.send(:scope, shard: 0, of: 2)
      scope_shard1 = job.send(:scope, shard: 1, of: 2)
      shard0_ids = scope_shard0.pluck(:id)
      shard1_ids = scope_shard1.pluck(:id)
      expect(shard0_ids & shard1_ids).to be_empty
      expect((shard0_ids + shard1_ids).sort).to eq(Score.where(source: "cpdl").pluck(:id).sort - [
        Score.find_by(external_id: "2").id,
        Score.find_by(external_id: "3").id,
        Score.find_by(external_id: "5").id
      ])
    end
  end

  describe "#build_delta" do
    let(:score) do
      Score.new(
        source: "cpdl", external_id: "9", title: "T",
        composer_normalized: "Bach, Johann Sebastian",
        voicing_status: "normalized",
        voicing: nil # Will be filled
      )
    end

    it "fills blank fields from parsed metadata" do
      parsed = { title: "T2", composer: "Bach", license: "CC0" }
      delta = job.send(:build_delta, score, parsed)
      expect(delta).to include(license: "CC0")
    end

    it "never overwrites composer_normalized when already set" do
      parsed = { composer_normalized: "WRONG", license: "CC0" }
      delta = job.send(:build_delta, score, parsed)
      expect(delta).not_to have_key(:composer_normalized)
    end

    it "always overwrites external_url with the canonical URL" do
      score.external_url = "https://old"
      parsed = { canonical_url: "https://new" }
      delta = job.send(:build_delta, score, parsed)
      expect(delta[:external_url]).to eq("https://new")
    end

    it "does not re-set voicing_status when already normalized" do
      parsed = { voicing_status: "pending" }
      delta = job.send(:build_delta, score, parsed)
      expect(delta).not_to have_key(:voicing_status)
    end

    it "skips fields the row already has populated (fill-blanks-only)" do
      score.license = "CC-BY"
      parsed = { license: "CC0" }
      delta = job.send(:build_delta, score, parsed)
      expect(delta).not_to have_key(:license)
    end
  end

  describe "#page_title_from_url" do
    # Real existing CPDL rows store URLs encoded by URI.encode_www_form_component,
    # which uses '+' for spaces and %xx for non-ASCII. Sample from the live DB:
    # "https://www.cpdl.org/wiki/index.php/%22Dans%22+ropte+Felen+%28Wilhelm+Peterson-Berger%29"
    it "decodes plus-encoded spaces and parenthesis escapes back to the wiki page title" do
      expect(job.send(:page_title_from_url, "https://www.cpdl.org/wiki/index.php/Ave+Maria+%28Bach%29"))
        .to eq("Ave Maria (Bach)")
    end

    it "decodes percent-encoded characters (UTF-8)" do
      expect(job.send(:page_title_from_url, "https://www.cpdl.org/wiki/index.php/Magn%C3%ADficat"))
        .to eq("Magníficat")
    end

    it "returns nil for URLs without the /wiki/index.php/ path segment" do
      expect(job.send(:page_title_from_url, "https://example.com/foo")).to be_nil
    end
  end

  describe "#perform" do
    before do
      Score.delete_all
      @stub_score = Score.create!(source: "cpdl", external_id: "100", title: "Stub",
                                  external_url: "https://www.cpdl.org/wiki/index.php/Stub_(disambiguation)")
      @recoverable_score = Score.create!(source: "cpdl", external_id: "101", title: "Real",
                                         external_url: "https://www.cpdl.org/wiki/index.php/Real_(Bach)")
    end

    it "marks stub-page rows as rag_failed with reason cpdl_stub" do
      allow_any_instance_of(CpdlImporter).to receive(:fetch_page_content).and_return(
        { "wikitext" => { "*" => "" }, "categories" => [], "title" => "Stub (disambiguation)" }
      )

      described_class.new.perform(limit: 1)

      @stub_score.reload
      expect(@stub_score.rag_status).to eq("failed")
      expect(@stub_score.rag_failure_reason).to eq("cpdl_stub")
    end

    it "updates recoverable rows with parsed metadata when MXL is found (extraction follows manual pipeline)" do
      @stub_score.destroy
      allow_any_instance_of(CpdlImporter).to receive(:fetch_page_content).and_return(
        { "wikitext" => { "*" => "[[File:Bach-Real.mxl]]{{Voicing|4|SATB}}" },
          "categories" => [], "title" => "Real (Bach)" }
      )
      allow_any_instance_of(CpdlImporter).to receive(:fetch_file_urls).and_return(
        pdf: nil, midi: nil, musicxml: "https://cpdl.org/Bach-Real.mxl"
      )

      described_class.new.perform(limit: 10)

      @recoverable_score.reload
      expect(@recoverable_score.mxl_path).to eq("https://cpdl.org/Bach-Real.mxl")
      expect(@recoverable_score.voicing).to eq("SATB")
      expect(@recoverable_score.voicing_status).to eq("normalized")
      expect(@recoverable_score.has_vocal).to be(true)
      expect(@recoverable_score.has_vocal_status).to eq("normalized")
      expect(@recoverable_score.extraction_status).to eq("pending") # left for ExtractPendingScoresJob
    end

    it "marks a row as cpdl_no_files when the page passes the content gate but yields no MXL/PDF/voicing" do
      # Page has {{CPDLno|123}} (passes content gate) but no [[File:...]] and no {{Voicing}}.
      allow_any_instance_of(CpdlImporter).to receive(:fetch_page_content).and_return(
        { "wikitext" => { "*" => "{{CPDLno|12345}}" }, "categories" => [], "title" => "Real (Bach)" }
      )
      allow_any_instance_of(CpdlImporter).to receive(:fetch_file_urls).and_return(
        pdf: nil, midi: nil, musicxml: nil
      )

      described_class.new.perform(limit: 10)

      @recoverable_score.reload
      expect(@recoverable_score.rag_status).to eq("failed")
      expect(@recoverable_score.rag_failure_reason).to eq("cpdl_no_files")
    end

    it "marks a row as cpdl_redirect_collision when another CPDL row already has the canonical URL" do
      # Match how the job constructs URLs: URI.encode_www_form_component uses '+' for spaces.
      canonical_url = "https://www.cpdl.org/wiki/index.php/Real+%28Bach%29"
      Score.create!(source: "cpdl", external_id: "999", title: "Real (already imported)",
                    external_url: canonical_url,
                    voicing: "SATB") # makes it ineligible for the scope, but reachable via the collision lookup

      allow_any_instance_of(CpdlImporter).to receive(:fetch_page_content).and_return(
        { "wikitext" => { "*" => "[[File:x.mxl]]" }, "categories" => [], "title" => "Real (Bach)" }
      )
      allow_any_instance_of(CpdlImporter).to receive(:fetch_file_urls).and_return(
        pdf: nil, midi: nil, musicxml: "https://cpdl.org/x.mxl"
      )

      described_class.new.perform(limit: 10)

      @recoverable_score.reload
      expect(@recoverable_score.rag_status).to eq("failed")
      expect(@recoverable_score.rag_failure_reason).to eq("cpdl_redirect_collision")
      expect(@recoverable_score.mxl_path).to be_nil # nothing written; collision blocks update
    end
  end
end
