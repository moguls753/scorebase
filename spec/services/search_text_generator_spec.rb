# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchTextGenerator do
  let(:client)    { instance_double(LlmClient) }
  let(:generator) { described_class.new(client: client) }

  describe "#template_for" do
    it "uses RICH_PROMPT when music21 extraction succeeded" do
      score = build(:score, source: "pdmx", extraction_status: :extracted)
      expect(generator.send(:template_for, score)).to eq(described_class::RICH_PROMPT)
    end

    it "uses SPARSE_PROMPT for vision-extracted SMD" do
      score = build(:score, :smd, extraction_status: :vision_extracted)
      expect(generator.send(:template_for, score)).to eq(described_class::SPARSE_PROMPT)
    end

    it "uses SPARSE_PROMPT for unextracted IMSLP scores" do
      score = build(:score, source: "imslp", extraction_status: :pending)
      expect(generator.send(:template_for, score)).to eq(described_class::SPARSE_PROMPT)
    end
  end

  describe "#build_sparse_metadata" do
    it "passes the score title through to metadata" do
      score = build(:score, :smd, title: "Good Rockin' Tonight", language: "Unspecified")
      metadata = generator.send(:build_sparse_metadata, score)
      expect(metadata[:title]).to eq("Good Rockin' Tonight")
      expect(metadata).not_to have_key(:language)
    end

    it "includes SMD-specific catalog fields when present" do
      score = build(:score, :smd,
                    artist: "Elvis Presley",
                    brand: "Hal Leonard",
                    arrangement_category: "Guitar",
                    smd_category: "Guitar Tab",
                    tags: "Blues-Jazz-Pop")
      metadata = generator.send(:build_sparse_metadata, score)
      expect(metadata).to include(
        artist: "Elvis Presley",
        brand: "Hal Leonard",
        arrangement_category: "Guitar",
        smd_category: "Guitar Tab",
        tags: "Blues-Jazz-Pop"
      )
    end
  end

  describe "#generate" do
    let(:prose) { "Motet is a canon on Example Tune. The catalogue lists Latin and English as the languages of this setting." }

    it "keeps the CPDL source note intact and appends only measured vocal ranges after generation" do
      score = build(:score, source: "cpdl", extraction_status: :extracted, title: "Motet", language: "Latin, English",
                    description: "A canon on ''Example Tune''. Soprano: c''–g''. Original clefs: c1, c3.", computed_difficulty: nil, pedagogical_grade: nil,
                    has_vocal: true, voicing: "SoloS", num_parts: 3, part_names: "Soprano, BC, BC", ambitus_semitones: 36,
                    pitch_range_per_part: { "Soprano" => { "low" => "F#4", "high" => "E5" }, "BC" => { "low" => "E2", "high" => "E3" } },
                    voice_ranges: { "Soprano" => 10, "BC" => 12 })
      expect(client).to receive(:chat_json) do |prompt|
        data = JSON.parse(prompt.match(%r{<data>\s*(.*?)\s*</data>}m)[1])
        expect(data).to include("title" => "Motet", "language" => "Latin, English", "cpdl_description" => score.description)
        expect(data).not_to include("ambitus", "vocal_part_ranges")
        { "description" => "#{prose} Original clefs: C1, C3." }
      end
      result = generator.generate(score)
      expect(result).to be_success
      expect(result.description).to eq("#{prose} Original clefs: C1, C3. Soprano: F#4–E5.")
    end

    it "does not guess ambiguous ranges or accept pitch limits supplied by the model" do
      score = build(:score, source: "cpdl", extraction_status: :extracted, has_vocal: true, voicing: "SoloB", num_parts: 2,
                    computed_difficulty: nil, pedagogical_grade: nil,
                    pitch_range_per_part: { "Voice" => { "low" => "F3", "high" => "E4" }, "Bass" => { "low" => "C3", "high" => "G4" } })
      allow(client).to receive(:chat_json).and_return("description" => prose)
      ["Voice, Piano", "Bass, Bass"].each do |names|
        score.part_names = names
        expect(generator.generate(score).description).to eq(prose)
      end
      allow(client).to receive(:chat_json).and_return("description" => "#{prose} The tenor ranges between F#4 and E5.")
      expect(generator.generate(score)).not_to be_success
    end
  end

  describe "#build_rich_metadata" do
    it "excludes SMD-specific catalog fields even when present on score" do
      score = build(:score, source: "pdmx",
                    ambitus_semitones: 36,
                    artist: "Should Not Appear",
                    brand: "Should Not Appear",
                    arrangement_category: "Should Not Appear",
                    smd_category: "Should Not Appear",
                    tags: "Should-Not-Appear")
      metadata = generator.send(:build_rich_metadata, score)
      expect(metadata).not_to include(:artist, :brand, :arrangement_category, :smd_category, :tags, :vocal_part_ranges)
      expect(metadata[:ambitus]).to eq("wide")
    end
  end
end
