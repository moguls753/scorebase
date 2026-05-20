# frozen_string_literal: true

require "rails_helper"

RSpec.describe CpdlImporter::VoicingTemplate do
  describe ".parse" do
    it "extracts num_parts and voicing from the standard form" do
      result = described_class.parse("...{{Voicing|4|SATB}}...")
      expect(result.num_parts).to eq(4)
      expect(result.voicing).to eq("SATB")
    end

    it "parses bare voicing without a numeric first arg" do
      result = described_class.parse("{{Voicing|SATB}}")
      expect(result.num_parts).to be_nil
      expect(result.voicing).to eq("SATB")
    end

    it "strips the |add=... tail" do
      result = described_class.parse("{{Voicing|4|SATB|add=divisi}}")
      expect(result.voicing).to eq("SATB")
    end

    it "preserves dot separators in voicing values" do
      result = described_class.parse("{{Voicing|4|SATB.SATB}}")
      expect(result.voicing).to eq("SATB.SATB")
    end

    it "takes the first segment of comma-separated alternatives" do
      result = described_class.parse("{{Voicing|6|SSAATB,AATTBB}}")
      expect(result.voicing).to eq("SSAATB")
    end

    it "maps single-letter solo forms to SoloX canonical" do
      result = described_class.parse("{{Voicing|1|S}}")
      expect(result.voicing).to eq("SoloS")
    end

    it "passes descriptive voicing forms through unchanged" do
      result = described_class.parse("{{Voicing|3|3 equal voices}}")
      expect(result.voicing).to eq("3 equal voices")
    end

    it "parses across newlines (multi-line template)" do
      result = described_class.parse("{{Voicing\n|4\n|SATB\n}}")
      expect(result.num_parts).to eq(4)
      expect(result.voicing).to eq("SATB")
    end

    it "skips empty positional segments after the part count" do
      result = described_class.parse("{{Voicing|4||SATB}}")
      expect(result.num_parts).to eq(4)
      expect(result.voicing).to eq("SATB")
    end

    it "returns a result with both fields nil when no template is present" do
      result = described_class.parse("no template here")
      expect(result.num_parts).to be_nil
      expect(result.voicing).to be_nil
    end
  end

  describe ".canonicalize" do
    it "strips |add=... tail and trims" do
      expect(described_class.canonicalize("SATB|add=divisi")).to eq("SATB")
    end

    it "takes first segment of comma alternation" do
      expect(described_class.canonicalize("SSAATB,AATTBB")).to eq("SSAATB")
    end

    it "maps 'Solo Soprano' to 'SoloS'" do
      expect(described_class.canonicalize("Solo Soprano")).to eq("SoloS")
    end

    it "returns nil for blank input" do
      expect(described_class.canonicalize("")).to be_nil
      expect(described_class.canonicalize(nil)).to be_nil
    end
  end
end
