# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmdStatusNormalizer do
  let(:score) do
    create(:score, :smd,
           composer: "Bach, Johann Sebastian", instruments: "Piano",
           period: "Baroque", period_status: "normalized",
           extraction_status: :vision_extracted)
  end

  describe "preconditions" do
    it "skips when not SMD" do
      non_smd = create(:score, source: "pdmx", extraction_status: :extracted)
      expect(described_class.new(non_smd).call.status).to eq(:skipped)
    end

    it "skips when extraction_status is not vision_extracted" do
      score.update!(extraction_status: :pending)
      result = described_class.new(score).call
      expect(result.status).to eq(:skipped)
      expect(result.reason).to eq("vision not yet run")
    end

    it "skips on the second run (already_fully_normalized)" do
      described_class.new(score).call
      expect(described_class.new(score.reload).call.status).to eq(:skipped)
    end
  end

  it "fills all status fields on a typical non-vocal score" do
    result = described_class.new(score).call
    score.reload

    expect(result.status).to eq(:ok)
    expect(score.composer_status).to    eq("normalized")
    expect(score.period_status).to      eq("normalized")
    expect(score.instruments_status).to eq("normalized")
    expect(score.extraction_status).to  eq("vision_extracted")
    expect(score.has_vocal_status).to   eq("normalized")
    expect(score.has_vocal).to          be false
    expect(score.voicing_status).to     eq("not_applicable")
    expect(score.grade_status).to       eq("not_applicable")
    expect(score.genre_status).to       eq("not_applicable")
  end

  it "marks composer_status not_applicable for placeholder composers" do
    score.update!(composer: "Anonymous")
    described_class.new(score).call
    expect(score.reload.composer_status).to eq("not_applicable")
  end

  it "has_vocal=true when keyword indicates vocal even if vision missed it" do
    score.update!(arrangement_category: "SATB Choir", has_vocal: false)
    described_class.new(score).call
    expect(score.reload.has_vocal).to be true
  end

  describe "instruments backfill" do
    it "derives instruments from arrangement_category when blank" do
      score.update!(instruments: "", arrangement_category: "Choir")
      described_class.new(score).call
      score.reload
      expect(score.instruments).to eq("Choir")
      expect(score.instruments_status).to eq("normalized")
    end

    it "uses smd_category to disambiguate Band arrangements" do
      score.update!(instruments: "", arrangement_category: "Band", smd_category: "Jazz Ensemble")
      described_class.new(score).call
      expect(score.reload.instruments).to eq("Jazz Ensemble")
    end

    it "preserves importer-set instruments rather than overwriting" do
      score.update!(instruments: "Flute, Piano", arrangement_category: "Choir")
      described_class.new(score).call
      expect(score.reload.instruments).to eq("Flute, Piano")
    end
  end

  describe "voicing" do
    it "extracts canonical abbreviation from arrangement_category" do
      score.update!(arrangement_category: "Choir SATB", has_vocal: true)
      described_class.new(score).call
      expect(score.reload.voicing).to eq("SATB")
    end

    it "derives voicing from named parts when no abbreviation present" do
      score.update!(arrangement_category: "Vocal Score", has_vocal: true,
                    part_names: "Soprano, Alto, Tenor, Bass, Piano")
      described_class.new(score).call
      expect(score.reload.voicing).to eq("SATB")
    end

    it "leaves status=pending for vocal scores with no parseable signal" do
      score.update!(arrangement_category: "Vocal Arrangement", has_vocal: true,
                    part_names: nil, smd_category: "Pop")
      described_class.new(score).call
      expect(score.reload.voicing_status).to eq("pending")
    end
  end

  describe "pedagogical_grade" do
    it "maps smd_category to ABRSM grade string" do
      score.update!(smd_category: "Easy Piano", pedagogical_grade: nil)
      described_class.new(score).call
      expect(score.reload.pedagogical_grade).to eq("Grade 2-3")
    end

    it "preserves an importer-set value rather than overwriting it" do
      score.update!(smd_category: "Easy Piano", pedagogical_grade: "Grade 1")
      described_class.new(score).call
      expect(score.reload.pedagogical_grade).to eq("Grade 1")
    end
  end

  describe "genre" do
    it "extracts plural and singular title forms (e.g. 'Carols')" do
      score.update!(title: "Three Carols for Christmas", tags: nil)
      described_class.new(score).call
      expect(score.reload.genre).to eq("Carol")
    end

    it "ignores 'Lied' to avoid the English past-tense collision" do
      score.update!(title: "He Lied When He Said Hello", tags: nil)
      described_class.new(score).call
      expect(score.reload.genre).to be_blank
    end

    it "excludes 'Mass' when followed by 'Choir' (it's the ensemble, not the form)" do
      score.update!(title: "Mass Choir Anthem", tags: nil)
      described_class.new(score).call
      expect(score.reload.genre).to eq("Anthem")
    end
  end
end
