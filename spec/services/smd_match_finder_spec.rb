# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmdMatchFinder do
  # Index rows: [id, title, composer, artist, price_usd]
  def index_for(*rows)
    described_class.build_index(rows)
  end

  describe ".normalize" do
    it "strips accents, punctuation and case" do
      expect(described_class.normalize("Dvořák: Songs, Op.55!")).to eq("dvorak songs op 55")
    end
  end

  describe ".surname" do
    it "takes the part before the comma" do
      expect(described_class.surname("Bach, Johann Sebastian")).to eq("bach")
    end

    it "falls back to the last word without a comma" do
      expect(described_class.surname("Aretha Franklin")).to eq("franklin")
    end
  end

  describe ".matches_for" do
    it "matches on title + composer surname across name orders" do
      index = index_for([ 1, "Locus Iste", "Anton Bruckner", nil, 9.99 ])

      expect(described_class.matches_for("Locus iste", "Bruckner, Anton", index)).to eq([ 1 ])
    end

    it "never matches a same-title piece by a different composer" do
      # Pin from the measured false-positive catalog: Robert Franz's Ave Maria
      # must not link to Schubert's, despite "Franz" appearing in both names.
      index = index_for([ 1, "Ave Maria", "Schubert, Franz", nil, 5.99 ])

      expect(described_class.matches_for("Ave Maria", "Franz, Robert", index)).to be_empty
    end

    it "matches via the artist field when the composer field does not" do
      index = index_for([ 1, "Nothing Else Matters", "Hetfield, James", "Metallica", 19.99 ])

      expect(described_class.matches_for("Nothing Else Matters", "Metallica", index)).to eq([ 1 ])
    end

    it "blocks single-word generic form titles even with matching composer" do
      index = index_for([ 1, "Minuet", "Bach, Johann Sebastian", nil, 4.99 ])

      expect(described_class.matches_for("Minuet", "Bach, Johann Sebastian", index)).to be_empty
    end

    it "allows non-generic single-word titles" do
      index = index_for([ 1, "Habanera", "Bizet, Georges", nil, 4.99 ])

      expect(described_class.matches_for("Habanera", "Bizet, Georges", index)).to eq([ 1 ])
    end

    it "returns nothing for a blank composer" do
      index = index_for([ 1, "Locus Iste", "Anton Bruckner", nil, 9.99 ])

      expect(described_class.matches_for("Locus Iste", nil, index)).to be_empty
    end

    it "ranks by price descending, then id, with nil prices last" do
      index = index_for(
        [ 1, "Locus Iste", "Anton Bruckner", nil, 9.99 ],
        [ 2, "Locus Iste", "Anton Bruckner", nil, nil ],
        [ 3, "Locus Iste", "Anton Bruckner", nil, 49.99 ],
        [ 4, "Locus Iste", "Anton Bruckner", nil, 49.99 ]
      )

      expect(described_class.matches_for("Locus Iste", "Bruckner, Anton", index)).to eq([ 3, 4, 1, 2 ])
    end

    it "prefers a set listing over an instrument-suffixed title" do
      index = index_for(
        [ 1, "Ave Maria - SATB", "Schubert, Franz", nil, 89.99 ],
        [ 2, "Ave Maria SATB", "Schubert, Franz", nil, 5.99 ]
      )

      expect(described_class.matches_for("Ave Maria SATB", "Schubert, Franz", index)).to eq([ 2, 1 ])
    end
  end
end
