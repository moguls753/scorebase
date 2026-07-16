# frozen_string_literal: true

require "rails_helper"

RSpec.describe BackfillGroupKeysJob, type: :job do
  let(:thumb) { "https://img.sheetmusic.direct/catalogue/product/hl-04493257-md.jpg" }
  let(:group_key) { "birds of a feather (arr. larry moore)|hl-04493257" }

  describe "#perform" do
    it "keys parts from title + thumbnail (pass 1)" do
      part = create(:score, :smd, title: "Birds of a Feather (arr. Larry Moore) - Trombone 2", thumbnail_url: thumb)

      described_class.perform_now

      expect(part.reload.group_key).to eq(group_key)
    end

    it "keys arranger bundles once their parts are keyed (pass 2)" do
      create(:score, :smd, title: "Birds of a Feather (arr. Larry Moore) - Trombone 2", thumbnail_url: thumb)
      bundle = create(:score, :smd, title: "Birds of a Feather (arr. Larry Moore)", thumbnail_url: thumb)

      described_class.perform_now

      expect(bundle.reload.group_key).to eq(group_key)
    end

    it "marks one representative per group, preferring the Full Score (pass 4)" do
      # Loser created first with the higher price, so the spec fails if the
      # Full Score tier is dropped and price/id decide instead.
      part = create(:score, :smd, title: "Birds of a Feather (arr. Larry Moore) - Trombone 2", thumbnail_url: thumb, price_usd: 11.99)
      full = create(:score, :smd, title: "Birds of a Feather (arr. Larry Moore) - Full Score", thumbnail_url: thumb, price_usd: 7.19)

      described_class.perform_now

      expect(full.reload.is_group_representative).to be true
      expect(part.reload.is_group_representative).to be_falsey
    end

    it "leaves standalone scores unkeyed" do
      solo = create(:score, :smd, title: "Just A Solo Piece", thumbnail_url: thumb)

      described_class.perform_now

      expect(solo.reload.group_key).to be_nil
      expect(solo.is_group_representative).to be_falsey
    end

    it "clears a stale key when a title no longer groups (self-healing)" do
      orphan = create(:score, :smd, title: "Renamed Standalone", thumbnail_url: thumb, group_key: "old|hl-04493257")

      described_class.perform_now

      expect(orphan.reload.group_key).to be_nil
    end

    it "is idempotent" do
      score = create(:score, :smd, title: "Birds of a Feather (arr. Larry Moore) - Full Score", thumbnail_url: thumb)
      described_class.perform_now
      before = score.reload.attributes.slice("group_key", "is_group_representative")

      described_class.perform_now

      expect(score.reload.attributes.slice("group_key", "is_group_representative")).to eq(before)
    end

    it "prefers the Conductor score when no Full Score exists" do
      part = create(:score, :smd, title: "Birds of a Feather (arr. Larry Moore) - Aux Percussion", thumbnail_url: thumb, price_usd: 11.99)
      conductor = create(:score, :smd, title: "Birds of a Feather (arr. Larry Moore) - Conductor Score", thumbnail_url: thumb, price_usd: 7.19)

      described_class.perform_now

      expect(conductor.reload.is_group_representative).to be true
      expect(part.reload.is_group_representative).to be_falsey
    end

    it "prefers the pricier row among same-tier parts" do
      # Cheaper row created first so id order diverges from price order —
      # otherwise this passes even if the price tiebreak is dropped.
      cheap = create(:score, :smd, title: "Birds of a Feather (arr. Larry Moore) - Aux Percussion", thumbnail_url: thumb, price_usd: 5.39)
      pricey = create(:score, :smd, title: "Birds of a Feather (arr. Larry Moore) - Trombone 2", thumbnail_url: thumb, price_usd: 11.99)

      described_class.perform_now

      expect(pricey.reload.is_group_representative).to be true
      expect(cheap.reload.is_group_representative).to be_falsey
    end

    it "breaks equal-price ties by id, deterministically" do
      first = create(:score, :smd, title: "Birds of a Feather (arr. Larry Moore) - Trombone 2", thumbnail_url: thumb, price_usd: 7.19)
      second = create(:score, :smd, title: "Birds of a Feather (arr. Larry Moore) - Aux Percussion", thumbnail_url: thumb, price_usd: 7.19)

      described_class.perform_now

      expect(first.reload.is_group_representative).to be true
      expect(second.reload.is_group_representative).to be_falsey
    end

    it "never makes a soft-deleted row the representative" do
      deleted_full = create(:score, :smd, title: "Birds of a Feather (arr. Larry Moore) - Full Score", thumbnail_url: thumb, deleted_at: Time.current)
      active_part = create(:score, :smd, title: "Birds of a Feather (arr. Larry Moore) - Trombone 2", thumbnail_url: thumb)

      described_class.perform_now

      expect(active_part.reload.is_group_representative).to be true
      expect(deleted_full.reload.is_group_representative).to be_falsey
    end

    it "clears a stale representative flag on a row that no longer qualifies" do
      stale = create(:score, :smd, title: "Ungrouped Solo Piece", thumbnail_url: thumb, is_group_representative: true)

      described_class.perform_now

      expect(stale.reload.is_group_representative).to be_falsey
    end

    it "returns exact per-pass counts" do
      create(:score, :smd, title: "Birds of a Feather (arr. Larry Moore) - Full Score", thumbnail_url: thumb)

      stats = described_class.perform_now

      expect(stats).to eq(part_keys: 1, bundle_keys: 0, parent_keys: 0, representatives: 1)
    end
  end

  describe "complete-set listings (pass 3)" do
    let(:set_group_key) { "birds of a feather|hl-04493257" }

    it "absorbs the set listing and makes it the representative" do
      # Set priced BELOW the Full Score, so only the bare-title tier can win —
      # the spec fails if that tier is dropped from the ranking.
      full = create(:score, :smd, title: "Birds of a Feather - Full Score", thumbnail_url: thumb, smd_category: "Concert Band", price_usd: 52.99)
      set = create(:score, :smd, title: "Birds of a Feather", thumbnail_url: thumb, smd_category: "Concert Band", price_usd: 9.99)

      described_class.perform_now

      expect(set.reload.group_key).to eq(set_group_key)
      expect(set.is_group_representative).to be true
      expect(full.reload.is_group_representative).to be_falsey
    end

    it "does not absorb a listing whose category differs from the group's parts" do
      create(:score, :smd, title: "Birds of a Feather - Full Score", thumbnail_url: thumb, smd_category: "Choir Instrumental Pak")
      vocal = create(:score, :smd, title: "Birds of a Feather", thumbnail_url: thumb, smd_category: "SATB Choir")

      described_class.perform_now

      expect(vocal.reload.group_key).to be_nil
      expect(vocal.is_group_representative).to be_falsey
    end

    it "never absorbs audio products" do
      create(:score, :smd, title: "Birds of a Feather - Full Score", thumbnail_url: thumb, smd_category: "SATB Choir Audio - Full Performance")
      audio = create(:score, :smd, title: "Birds of a Feather", thumbnail_url: thumb, smd_category: "SATB Choir Audio - Full Performance")

      described_class.perform_now

      expect(audio.reload.group_key).to be_nil
    end

    it "leaves all bare listings visible when several share the group's code" do
      create(:score, :smd, title: "Birds of a Feather - Full Score", thumbnail_url: thumb, smd_category: "Concert Band")
      twins = create_list(:score, 2, :smd, title: "Birds of a Feather", thumbnail_url: thumb, smd_category: "Concert Band")

      described_class.perform_now

      expect(twins.each(&:reload).map(&:group_key)).to all(be_nil)
    end

    it "excludes the set listing and soft-deleted rows from the PARTS badge" do
      full = create(:score, :smd, title: "Birds of a Feather - Full Score", thumbnail_url: thumb, smd_category: "Concert Band")
      part = create(:score, :smd, title: "Birds of a Feather - Trombone 2", thumbnail_url: thumb, smd_category: "Concert Band")
      create(:score, :smd, title: "Birds of a Feather - Viola", thumbnail_url: thumb, smd_category: "Concert Band", deleted_at: Time.current)
      set = create(:score, :smd, title: "Birds of a Feather", thumbnail_url: thumb, smd_category: "Concert Band")

      described_class.perform_now

      expect(set.reload.group_parts_count).to eq(2)
      expect(set.grouped_parts).to contain_exactly(full, part)
    end

    it "surfaces the same card in search and browse dedup" do
      full = create(:score, :smd, title: "Birds of a Feather - Full Score", thumbnail_url: thumb, smd_category: "Concert Band")
      part = create(:score, :smd, title: "Birds of a Feather - Trombone 2", thumbnail_url: thumb, smd_category: "Concert Band")
      set = create(:score, :smd, title: "Birds of a Feather", thumbnail_url: thumb, smd_category: "Concert Band", price_usd: 52.99)

      described_class.perform_now

      search_ids = Score.search("birds feather").pluck(:id)
      expect(search_ids).to include(set.id)
      expect(search_ids).not_to include(full.id, part.id)
      expect(Score.deduplicate_arrangements.where(group_key: set.reload.group_key)).to contain_exactly(set)
    end
  end
end
