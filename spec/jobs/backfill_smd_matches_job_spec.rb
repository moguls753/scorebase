# frozen_string_literal: true

require "rails_helper"

RSpec.describe BackfillSmdMatchesJob, type: :job do
  let!(:free) { create(:score, title: "Locus Iste", composer: "Bruckner, Anton") }

  def smd_edition(price:, **attrs)
    create(:score, :smd, title: "Locus Iste", composer: "Anton Bruckner", artist: nil, price_usd: price, **attrs)
  end

  describe "#perform" do
    it "creates ranked links, priciest edition first" do
      cheap = smd_edition(price: 5.99)
      set = smd_edition(price: 54.99)

      described_class.perform_now

      expect(free.professional_editions).to eq([ set, cheap ])
    end

    it "caps links at three" do
      4.times { |i| smd_edition(price: 10.0 + i) }

      described_class.perform_now

      expect(free.smd_match_links.count).to eq(3)
    end

    it "never links a hidden group member" do
      smd_edition(price: 9.99, group_key: "locus iste|hl-1", is_group_representative: nil)

      described_class.perform_now

      expect(free.smd_match_links).to be_empty
    end

    it "never links anything to an SMD score" do
      smd_edition(price: 9.99)
      other_smd = smd_edition(price: 5.99)

      described_class.perform_now

      expect(other_smd.smd_match_links).to be_empty
    end

    it "writes nothing on an unchanged rerun" do
      smd_edition(price: 9.99)
      described_class.perform_now
      before = ScoreSmdMatch.order(:id).pluck(:id, :updated_at)

      described_class.perform_now

      expect(ScoreSmdMatch.order(:id).pluck(:id, :updated_at)).to eq(before)
    end

    it "swaps ranks without violating uniqueness" do
      first = smd_edition(price: 20.0)
      second = smd_edition(price: 10.0)
      described_class.perform_now

      second.update_column(:price_usd, 30.0)
      described_class.perform_now

      expect(free.professional_editions).to eq([ second, first ])
    end

    it "removes links whose target was soft-deleted" do
      edition = smd_edition(price: 9.99)
      described_class.perform_now

      edition.update_column(:deleted_at, Time.current)
      described_class.perform_now

      expect(free.smd_match_links).to be_empty
    end

    it "keeps suppressed rows dead and fills their slot with the next edition" do
      editions = 4.times.map { |i| smd_edition(price: 40.0 - (i * 10)) }
      described_class.perform_now

      free.smd_match_links.find_by(rank: 1).update!(suppressed: true)
      described_class.perform_now

      expect(free.professional_editions).to eq(editions[1..3])
      expect(free.smd_match_links.where(suppressed: true).count).to eq(1)
    end

    it "returns per-run stats" do
      smd_edition(price: 9.99)

      stats = described_class.perform_now

      expect(stats).to eq(matched_scores: 1, created: 1, removed: 0, unchanged: 0)
    end
  end
end
