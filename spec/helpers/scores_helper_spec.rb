require 'rails_helper'

RSpec.describe ScoresHelper, type: :helper do
  describe '#format_smd_price' do
    let(:score) { build(:score, :smd) }

    it 'formats USD price' do
      expect(helper.format_smd_price(score)).to eq("$7.19")
    end

    it 'returns nil when price is blank' do
      score.price_usd = nil
      expect(helper.format_smd_price(score)).to be_nil
    end
  end

  describe '#smd_on_sale?' do
    it 'returns true when original price exceeds current' do
      score = build(:score, :smd_on_sale)
      expect(helper.smd_on_sale?(score)).to be true
    end

    it 'returns false when no original price' do
      score = build(:score, :smd)
      expect(helper.smd_on_sale?(score)).to be false
    end
  end

  describe '#format_smd_price_with_sale' do
    it 'returns hash with current price only when not on sale' do
      score = build(:score, :smd)
      expect(helper.format_smd_price_with_sale(score)).to eq({ current: "$7.19" })
    end

    it 'returns hash with current and original when on sale' do
      score = build(:score, :smd_on_sale)
      result = helper.format_smd_price_with_sale(score)
      expect(result[:current]).to eq("$7.19")
      expect(result[:original]).to eq("$8.99")
    end
  end
end
