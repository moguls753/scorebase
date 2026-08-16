# frozen_string_literal: true

require "rails_helper"

# The converge itself is shared with BackfillSmdMatchesJob and covered there.
# What is Stretta's own is which editions are allowed into the index at all.
RSpec.describe BackfillStrettaMatchesJob do
  let!(:free) { create(:score, :pdmx, title: "Locus iste", composer: "Bruckner, Anton", instruments: "Voice") }

  def edition(**overrides)
    create(:score, :stretta, title: "Locus iste", composer: "Bruckner, Anton",
                             instruments: "Voice", **overrides)
  end

  it "links a free score to a Stretta edition of the same work" do
    published = edition

    described_class.new.perform

    expect(free.reload.stretta_editions).to eq([ published ])
  end

  # A backing track is not an edition anyone browsing sheet music buys.
  it "never offers an audio product" do
    edition(group_rank: 90)

    described_class.new.perform

    expect(free.reload.stretta_editions).to be_empty
  end

  it "never offers a hidden group member" do
    edition(group_key: "g", is_group_representative: nil)

    described_class.new.perform

    expect(free.reload.stretta_editions).to be_empty
  end

  it "never offers a row suppressed as a cross-source duplicate" do
    winner = create(:score, :smd, title: "Locus iste")
    edition(duplicate_of_id: winner.id)

    described_class.new.perform

    expect(free.reload.stretta_editions).to be_empty
  end
end
