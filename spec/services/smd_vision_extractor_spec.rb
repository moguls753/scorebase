# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmdVisionExtractor do
  let(:score) do
    create(:score, :smd,
           preview_image_url: "https://s3.amazonaws.com/halleonard-pagepreviews/HL_DDS_test.png")
  end

  def stub_response(payload)
    allow_any_instance_of(described_class).to receive(:fetch_extraction).and_return(payload)
  end

  describe "#call" do
    context "when preview_image_url is missing" do
      it "returns skipped" do
        score.update!(preview_image_url: nil)
        result = described_class.new(score).call
        expect(result.status).to eq(:skipped)
      end
    end

    context "when already processed" do
      it "returns skipped" do
        score.update!(extraction_status: :vision_extracted)
        result = described_class.new(score).call
        expect(result.status).to eq(:skipped)
      end
    end

    context "with a typical vocal-score response" do
      before do
        stub_response(
          "is_music_score" => true,
          "tempo_marking" => "Allegro Moderato (♩ = 120)",
          "time_signature" => "4/4",
          "key_signature" => "B-flat major",
          "voice_or_instrument_labels" => ["Soprano", "Alto", "Tenor", "Bass", "Piano"],
          "first_lyrics_line" => "May-be this time",
          "lyrics_language" => "EN",
          "dedication_or_subtitle" => "From Cabaret",
          "arranger" => "ED LOJESKI"
        )
      end

      it "populates mapped columns" do
        described_class.new(score).call
        score.reload

        expect(score.tempo_marking).to eq("allegro moderato (♩ = 120)")
        expect(score.tempo_bpm).to eq(120)
        expect(score.time_signature).to eq("4/4")
        expect(score.key_signature).to eq("B- major")
        expect(score.part_names).to eq("Soprano, Alto, Tenor, Bass, Piano")
        expect(score.has_extracted_lyrics).to be true
        expect(score.lyrics_language).to eq("en")
        expect(score.has_vocal).to be true
        expect(score.extraction_status).to eq("vision_extracted")
        expect(score.extracted_at).to be_present
      end
    end

    context "with an instrumental score (no lyrics, no vocal labels)" do
      before do
        stub_response(
          "is_music_score" => true,
          "tempo_marking" => "Maestoso",
          "time_signature" => "4/4",
          "key_signature" => "G major",
          "voice_or_instrument_labels" => ["VIOLIN 2"],
          "first_lyrics_line" => nil,
          "lyrics_language" => nil,
          "dedication_or_subtitle" => nil,
          "arranger" => "LARRY MOORE"
        )
      end

      it "sets has_vocal=false and does not flag lyrics" do
        described_class.new(score).call
        score.reload

        expect(score.has_extracted_lyrics).to be_falsey
        expect(score.lyrics_language).to be_nil
        expect(score.has_vocal).to be false
        expect(score.part_names).to eq("VIOLIN 2")
      end
    end

    context "when image is not a music score" do
      before { stub_response("is_music_score" => false) }

      it "marks processed but leaves data fields untouched" do
        described_class.new(score).call
        score.reload

        expect(score.extraction_status).to eq("vision_extracted")
        expect(score.tempo_marking).to be_nil
        expect(score.time_signature).to be_nil
      end
    end
  end

  describe "key signature normalization" do
    [
      ["B-flat major", "B- major"],
      ["E-flat minor", "E- minor"],
      ["C-sharp minor", "C# minor"],
      ["F-sharp major", "F# major"],
      ["B♭ major",    "B- major"],
      ["F♯ minor",    "F# minor"],
      ["G major",     "G major"],
      ["A minor",     "A minor"]
    ].each do |input, expected|
      it "normalizes '#{input}' to '#{expected}'" do
        score
        allow_any_instance_of(described_class).to receive(:fetch_extraction)
          .and_return("is_music_score" => true, "key_signature" => input)
        described_class.new(score).call
        expect(score.reload.key_signature).to eq(expected)
      end
    end
  end

  describe "BPM extraction" do
    [
      ["Allegro (♩ = 120)", 120],
      ["Moderato ♩=96",      96],
      ["J = 78",             78],
      ["Lively (♩ = ca. 126)", 126],
      ["= 124",              124],
      ["Slowly",             nil],
      ["Andante",            nil]
    ].each do |input, expected|
      it "extracts #{expected.inspect} from '#{input}'" do
        score
        allow_any_instance_of(described_class).to receive(:fetch_extraction)
          .and_return("is_music_score" => true, "tempo_marking" => input)
        described_class.new(score).call
        expect(score.reload.tempo_bpm).to eq(expected)
      end
    end
  end

  describe ".already_processed?" do
    it "returns true when extraction_status is vision_extracted" do
      score.update!(extraction_status: :vision_extracted)
      expect(described_class.already_processed?(score)).to be true
    end

    it "returns false when extraction_status is pending" do
      expect(described_class.already_processed?(score)).to be false
    end

    it "returns false when extraction_status is extracted (real music21)" do
      score.update!(extraction_status: :extracted)
      expect(described_class.already_processed?(score)).to be false
    end
  end
end
