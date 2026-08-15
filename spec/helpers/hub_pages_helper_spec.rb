require 'rails_helper'

RSpec.describe HubPagesHelper, type: :helper do
  describe '#instrument_part_badge' do
    it 'names the matched part when the card badge does not' do
      score = build(:score, main_instrument: "Choir", instruments: "SATB, Organ")
      expect(helper.instrument_part_badge(score, "Organ")).to eq("incl. Organ")
    end

    it 'stays silent when the card badge already names the instrument' do
      score = build(:score, main_instrument: "Organ", instruments: "Organ")
      expect(helper.instrument_part_badge(score, "Organ")).to be_nil
    end

    it 'stays silent without a page instrument' do
      score = build(:score, main_instrument: "Choir", instruments: "SATB, Organ")
      expect(helper.instrument_part_badge(score, nil)).to be_nil
    end

    it 'matches on the English needle but renders the localized label' do
      score = build(:score, main_instrument: "Choir", instruments: "SATB, Organ")
      I18n.with_locale(:de) do
        expect(helper.instrument_part_badge(score, "Organ", "Orgel")).to eq("inkl. Orgel")
      end
    end

    it 'stays silent when only a decoy instrument matches' do
      score = build(:score, main_instrument: "Choir", instruments: "SATB, Flute")
      expect(helper.instrument_part_badge(score, "Lute")).to be_nil
    end

    it 'ignores a decoy in the card badge when the parts list names the instrument' do
      score = build(:score, main_instrument: "Harpsichord", instruments: "Harpsichord, Harp")
      expect(helper.instrument_part_badge(score, "Harp")).to eq("incl. Harp")
    end

    it 'still matches compound and plural part names' do
      score = build(:score, main_instrument: "Choir", instruments: "SATB, Violoncello")
      expect(helper.instrument_part_badge(score, "Cello")).to eq("incl. Cello")
    end
  end
end
