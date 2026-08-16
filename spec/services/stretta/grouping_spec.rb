# frozen_string_literal: true

require "rails_helper"

RSpec.describe Stretta::Grouping do
  def product(**overrides)
    { vendor: "Carus Verlag", title: "Missa brevis", subtitle: "F-Dur",
      instrument: "gemischter Chor (SATB), Orgel", itemtype: "Partitur",
      authors: [{ role: "author", name: "Hans Leitner", slug: "hans-leitner" }] }.merge(overrides)
  end

  describe ".key" do
    it "prefixes with the source so a key can never collide with an SMD group" do
      expect(described_class.key(product)).to start_with("stretta:")
    end

    # Without the scoring, one Marc Reift band collapsed 464 arrangements for 230
    # different scorings into a single group, hiding 463 sellable products.
    it "separates two scorings of the same title" do
      brass = described_class.key(product(instrument: "2 Trompeten, Posaune"))
      choir = described_class.key(product)

      expect(brass).not_to eq(choir)
    end

    it "keeps a score and its parts together" do
      score = described_class.key(product(itemtype: "Partitur"))
      part  = described_class.key(product(itemtype: "Einzelstimme Trompete 1"))

      expect(score).to eq(part)
    end

    # Separately priced, separately bought: two products, two cards.
    it "separates a printed edition from its download" do
      print = described_class.key(product(product_type: "physical"))
      download = described_class.key(product(product_type: "dl_marcreift"))

      expect(print).not_to eq(download)
    end

    it "ignores author order" do
      one = described_class.key(product(authors: [{ slug: "a" }, { slug: "b" }]))
      two = described_class.key(product(authors: [{ slug: "b" }, { slug: "a" }]))

      expect(one).to eq(two)
    end

    it "falls back to the author name when there is no slug" do
      expect(described_class.key(product(authors: [{ name: "Wild Walter" }]))).to include("wild walter")
    end

    it "falls back to the order number when there is no author at all" do
      expect(described_class.key(product(authors: [], order_no: "CV 2.170/05"))).to include("cv 2 170 05")
    end

    # "stretta:Wertach||||" collected 69 unrelated rows.
    it "returns nothing without a title rather than a key of empty fields" do
      expect(described_class.key(product(title: ""))).to be_nil
    end
  end

  # The rules were derived and measured in Python; this fixture is that
  # measurement's own examples. If the two drift, the break rates in the report
  # stop describing this code.
  describe ".order_stem" do
    let(:rules) { JSON.parse(Rails.root.join("spec/fixtures/stretta_stem_rules.json").read) }

    it "reproduces every measured example" do
      mismatches = rules.fetch("rules").flat_map do |vendor, rule|
        rule.fetch("examples").filter_map do |order_no, expected|
          actual = described_class.order_stem(vendor, order_no)
          { vendor: vendor, order_no: order_no, expected: expected.to_s, actual: actual } if actual != expected.to_s
        end
      end

      expect(mismatches).to be_empty
    end

    # Schott and Hal Leonard number every component of a publication separately,
    # so the best available rule tore 34% of Schott's part sets apart.
    it "gives nothing to a publisher with no safe rule" do
      rules.fetch("rejected").each_key do |vendor|
        expect(described_class.order_stem(vendor, "C 44568")).to eq("")
      end
    end

    it "never falls back to the raw number when the rule does not match" do
      expect(described_class.order_stem("Carus Verlag", "something else")).to eq("")
    end
  end

  describe ".rank" do
    it "puts the fullest product first and single parts last" do
      expect(described_class.rank("Partitur, Stimmen")).to be < described_class.rank("Partitur")
      expect(described_class.rank("Partitur")).to be < described_class.rank("Einzelstimme Trompete 1")
    end

    # First match wins, so the specific forms have to precede the generic ones.
    it "reads a compound itemtype by its leading product, not by a substring" do
      expect(described_class.rank("Klavierpartitur, Solostimme")).to eq(described_class.rank("Partitur"))
      expect(described_class.rank("Notenbuch, Playback-CD")).to eq(described_class.rank("Notenbuch"))
      expect(described_class.rank("Tuba (Orchesterstimme)")).to eq(described_class.rank("Einzelstimme"))
    end
  end
end
