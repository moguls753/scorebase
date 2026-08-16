# frozen_string_literal: true

require "rails_helper"

RSpec.describe StrettaMatchFinder do
  def index_for(rows)
    described_class.build_index(rows)
  end

  # [id, title, composer, price_eur, instruments, group_rank]
  let(:rows) do
    [
      [1, "Locus iste", "Bruckner, Anton", 4.5, "Voice", 20],
      [2, "Locus iste", "Bruckner, Anton", 90.0, "Voice", 70]
    ]
  end

  it "matches on title plus composer surname" do
    expect(described_class.matches_for("Locus iste", "Anton Bruckner", index_for(rows))).to include(1)
  end

  it "never matches on title alone" do
    expect(described_class.matches_for("Locus iste", nil, index_for(rows))).to be_empty
  end

  # ß has no NFKD decomposition, so it used to become a space and split the word.
  it "normalises the sharp s so a German title still matches" do
    index = index_for([[1, "Großer Gott", "Leitner, Hans", 5.0, "Organ", 10]])

    expect(described_class.matches_for("Grosser Gott", "Hans Leitner", index)).to eq([1])
  end

  # The same composer wrote several; title plus surname is not identity here.
  it "stoplists a generic form title in German and in Latin" do
    index = index_for([[1, "Messe", "Palestrina", 9.0, "Voice", 10],
                       [2, "Agnus Dei", "Palestrina", 9.0, "Voice", 10]])

    expect(described_class.matches_for("Messe", "Palestrina", index)).to be_empty
    expect(described_class.matches_for("Agnus Dei", "Palestrina", index)).to be_empty
  end

  # A single orchestral part is never a purchase for a browsing user, however well
  # the scoring matches — so the choral score outranks it despite the lower price.
  it "ranks a playable edition above a single part" do
    expect(described_class.matches_for("Locus iste", "Bruckner", index_for(rows))).to eq([1, 2])
  end

  it "floats a matching instrument family to the top" do
    mixed = [[1, "Suite", "Bach", 9.0, "Trumpet", 10], [2, "Suite", "Bach", 5.0, "Piano", 10]]

    expect(described_class.matches_for("Suite", "Bach", index_for(mixed), free_family: :piano).first).to eq(2)
  end
end
