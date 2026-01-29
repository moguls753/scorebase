require 'rails_helper'

RSpec.describe ScoresHelper, type: :helper do
  describe '#format_smd_price' do
    let(:score) { build(:score, :smd) }

    it 'shows price for English locale' do
      I18n.with_locale(:en) do
        expect(helper.format_smd_price(score)).to eq("$7.19")
      end
    end

    it 'hides price for German locale' do
      I18n.with_locale(:de) do
        expect(helper.format_smd_price(score)).to be_nil
      end
    end
  end

  describe '#smd_on_sale?' do
    it 'detects sale when original price exceeds current' do
      score = build(:score, :smd_on_sale)
      expect(helper.smd_on_sale?(score)).to be true
    end
  end
end
