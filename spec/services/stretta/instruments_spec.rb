# frozen_string_literal: true

require "rails_helper"

RSpec.describe Stretta::Instruments do
  # The tokenizer was measured in Python and ported; this fixture is 38 real
  # catalogue values with the token list the measurement produced. If the two
  # drift, the coverage figures in the report stop describing this code.
  describe "tokenizer parity with the measured pipeline" do
    let(:cases) { JSON.parse(Rails.root.join("spec/fixtures/stretta_tokenizer_cases.json").read) }

    # Compared as sets: the fixture stores them sorted, while the tokenizer keeps
    # source order so "Singstimme, Klavier" displays as "Voice, Piano".
    it "reproduces the expected tokens for every real value" do
      mismatches = cases.filter_map do |example|
        actual = described_class.tokens(example["input"]).sort
        { input: example["input"], why: example["why"],
          expected: example["expected"], actual: actual } if actual != example["expected"].sort
      end

      expect(mismatches).to be_empty
    end
  end

  describe ".parse" do
    it "maps a German scoring list to the English vocabulary" do
      expect(described_class.parse("2 Trompeten (C), 2 Posaunen, Tuba, Orgel"))
        .to eq("Trumpet, Trombone, Tuba, Organ")
    end

    it "keeps an ensemble as a display term" do
      expect(described_class.parse("sinfonisches Blasorchester")).to eq("Wind Band")
    end

    it "returns nothing when the scoring maps to nothing" do
      expect(described_class.parse("Melodieinstrument")).to be_nil
    end
  end

  # An ensemble term is not in VALID_INSTRUMENTS, so it can never open an
  # instrument hub the row has no instrument for.
  describe ".normalized?" do
    it "is true for an instrument and false for an ensemble alone" do
      expect(described_class.normalized?("Orgel")).to be true
      expect(described_class.normalized?("sinfonisches Blasorchester")).to be false
    end
  end

  describe ".voicing" do
    it "reads a spelled-out code out of the brackets" do
      expect(described_class.voicing("gemischter Chor (SATB) a cappella")).to eq("SATB")
    end

    # Measured: ungated, the bracket test is wrong on 4.22% of its hits, almost all
    # of them consorts where the letters are recorder sizes.
    it "ignores a bracketed code in a row with no vocal word at all" do
      expect(described_class.voicing("4 Blockflöten (SATB)")).to be_nil
    end

    # SSA is 61% of Frauenchor rows that spell a code; SSAA is 23%.
    it "defaults a women's choir to SSA, the majority spelling" do
      expect(described_class.voicing("Frauenchor, Klavier")).to eq("SSA")
    end

    # "women's choir" contains "men's choir" as a substring.
    it "does not read a women's choir as a men's choir" do
      expect(described_class.voicing("women's choir")).to eq("SSA")
    end

    # Only 4% of Kinderchor rows ever spell a code, and they disagree.
    it "refuses to guess for a children's choir" do
      expect(described_class.voicing("Kinderchor, Orgel")).to be_nil
    end

    it "never returns German plain text, which LIKE-based voicing scopes would mis-file" do
      %w[Frauenchor Männerchor].each do |ensemble|
        expect(described_class.voicing(ensemble)).to match(/\A[SATB]+\z/)
      end
    end
  end

  # These land the rows in the ensemble hubs that already exist, so every value has
  # to be one the hub builder actually knows — a typo would file rows under a
  # category with no page.
  describe ".hub_category" do
    it "maps Stretta's ensembles onto the existing hub categories" do
      expect(described_class.hub_category("sinfonisches Blasorchester")).to eq("Concert Band")
      expect(described_class.hub_category("gemischter Chor (SATB) a cappella")).to eq("SATB Choir")
      expect(described_class.hub_category("Streichorchester")).to eq("Orchestra")
    end

    it "reads a choral work with orchestra as choral" do
      expect(described_class.hub_category("gemischter Chor (SATB), Orchester")).to eq("SATB Choir")
    end

    it "falls back to plain Choir when no code is spelled out" do
      expect(described_class.hub_category("Chor, Klavier")).to eq("Choir")
    end

    # The display vocabulary calls a quintet a brass band; the hubs must not.
    it "tells a brass band from a brass quintet" do
      expect(described_class.hub_category("Brass Band")).to eq("Brass Band")
      expect(described_class.hub_category("Blechbläserquintett")).to eq("Brass Ensemble")
    end

    it "returns nothing for a solo instrument" do
      expect(described_class.hub_category("Klavier")).to be_nil
    end

    it "only ever names a category the hub builder knows" do
      categories = ["Blasorchester", "Orchester", "Streichorchester", "Bigband", "Marschmusik",
                    "Brass Band", "Blechbläserquintett", "Kammerensemble"].filter_map do |word|
        described_class.hub_category(word)
      end
      categories += Stretta::Instruments::CHOIR_CODES.map { |code| described_class.hub_category("Chor (#{code})") }

      expect(categories.compact.uniq).to all(be_in(HubDataBuilder::ENSEMBLE_CATEGORIES_FLAT))
    end
  end
end
