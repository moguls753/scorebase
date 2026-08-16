# frozen_string_literal: true

require "rails_helper"

RSpec.describe PartnerEditions do
  let(:free) { create(:score, title: "Casta Diva", composer: "Bellini", instruments: "Voice, Piano") }

  def contest(smd_instrument, stretta_instruments)
    smd = create(:score, :smd, title: "Casta Diva", main_instrument: smd_instrument)
    stretta = create(:score, :stretta, title: "Casta Diva", instruments: stretta_instruments)
    ScoreSmdMatch.create!(score: free, smd_score: smd, rank: 1)
    ScoreStrettaMatch.create!(score: free, stretta_score: stretta, rank: 1)
    [ smd, stretta ]
  end

  it "shows the edition that fits the free score, not the incumbent" do
    smd, stretta = contest("Piano", "Voice, Piano")

    result = described_class.for(free.reload)

    expect(result.stretta).to eq([ stretta ])
    expect(result.smd).not_to include(smd)
  end

  it "keeps SMD when the Stretta edition fits worse" do
    smd, stretta = contest("Piano", "Trumpet")

    result = described_class.for(free.reload)

    expect(result.smd).to eq([ smd ])
    expect(result.stretta).not_to include(stretta)
  end

  # Both are real products from real shops; at equal fit the reader's locale is the
  # only thing left that distinguishes them.
  describe "when both fit equally" do
    it "shows the German shop on the German locale" do
      _smd, stretta = contest("Piano", "Voice, Piano")
      other = create(:score, :stretta, title: "Casta Diva", instruments: "Voice, Piano")
      ScoreStrettaMatch.create!(score: free, stretta_score: other, rank: 2)

      result = I18n.with_locale(:de) { described_class.for(free.reload) }

      expect(result.stretta).to include(stretta)
      expect(result.smd).to be_empty
    end

    it "keeps SMD elsewhere" do
      smd = create(:score, :smd, title: "Casta Diva", main_instrument: "Choir")
      stretta = create(:score, :stretta, title: "Casta Diva", instruments: "Voice")
      ScoreSmdMatch.create!(score: free, smd_score: smd, rank: 1)
      ScoreStrettaMatch.create!(score: free, stretta_score: stretta, rank: 1)

      result = I18n.with_locale(:en) { described_class.for(free.reload) }

      expect(result.smd).to eq([ smd ])
      expect(result.stretta).to be_empty
    end
  end

  it "shows both when they are editions of different works" do
    smd = create(:score, :smd, title: "Casta Diva", main_instrument: "Piano")
    stretta = create(:score, :stretta, title: "Norma Overture", instruments: "Voice")
    ScoreSmdMatch.create!(score: free, smd_score: smd, rank: 1)
    ScoreStrettaMatch.create!(score: free, stretta_score: stretta, rank: 1)

    result = described_class.for(free.reload)

    expect(result.smd).to eq([ smd ])
    expect(result.stretta).to eq([ stretta ])
  end

  it "leaves a single partner's editions untouched" do
    smd = create(:score, :smd, title: "Casta Diva", main_instrument: "Piano")
    ScoreSmdMatch.create!(score: free, smd_score: smd, rank: 1)

    expect(described_class.for(free.reload)).to have_attributes(smd: [ smd ], stretta: [])
  end
end
