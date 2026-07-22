# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmdMatchFinder do
  # Index rows: [id, title, composer, artist, price_usd, main_instrument]
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

  describe ".free_family" do
    it "checks is_instrumental first, then voicing/is_instrumental=false, then the instruments text" do
      expect(described_class.free_family("SATB", true, "Piano")).to eq(:piano)
      expect(described_class.free_family("SATB", nil, "Piano")).to eq(:vocal)
      expect(described_class.free_family(nil, false, "Piano")).to eq(:vocal)
      expect(described_class.free_family(nil, true, "Piano, Orchestra")).to eq(:piano)
      expect(described_class.free_family(nil, nil, nil)).to eq(:other)
    end

    it "does not misread register-prefixed winds ('Alto Sax', 'flute') as vocal or guitar" do
      expect(described_class.free_family(nil, true, "Alto Saxophone")).to eq(:winds)
      expect(described_class.free_family(nil, true, "Flute, B♭ Clarinet")).to eq(:winds)
    end
  end

  describe "instrument-relevant ranking" do
    it "floats a same-family edition above a pricier off-instrument one" do
      index = index_for(
        [ 1, "Fur Elise", "Beethoven, Ludwig", nil, 9.99, "Guitar" ],
        [ 2, "Fur Elise", "Beethoven, Ludwig", nil, 5.99, "Piano" ]
      )

      expect(described_class.matches_for("Fur Elise", "Beethoven, Ludwig", index, free_family: :piano)).to eq([ 2, 1 ])
    end

    it "keeps plain price order when the free family is unknown" do
      index = index_for(
        [ 1, "Fur Elise", "Beethoven, Ludwig", nil, 5.99, "Piano" ],
        [ 2, "Fur Elise", "Beethoven, Ludwig", nil, 9.99, "Guitar" ]
      )

      expect(described_class.matches_for("Fur Elise", "Beethoven, Ludwig", index)).to eq([ 2, 1 ])
    end

    it "sinks a pricey large-ensemble edition below smaller ones off-family, but keeps it for a band score" do
      index = index_for(
        [ 1, "Homeward Bound", "Whitacre, Eric", nil, 64.99, "Band" ],
        [ 2, "Homeward Bound", "Whitacre, Eric", nil, 7.99, "Piano" ]
      )

      expect(described_class.matches_for("Homeward Bound", "Whitacre, Eric", index, free_family: :vocal)).to eq([ 2, 1 ])
      expect(described_class.matches_for("Homeward Bound", "Whitacre, Eric", index, free_family: :band).first).to eq(1)
    end
  end
end
