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

    it "marks one representative per group, preferring the Full Score (pass 3)" do
      full = create(:score, :smd, title: "Birds of a Feather (arr. Larry Moore) - Full Score", thumbnail_url: thumb)
      part = create(:score, :smd, title: "Birds of a Feather (arr. Larry Moore) - Trombone 2", thumbnail_url: thumb)

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
      conductor = create(:score, :smd, title: "Birds of a Feather (arr. Larry Moore) - Conductor Score", thumbnail_url: thumb)
      part = create(:score, :smd, title: "Birds of a Feather (arr. Larry Moore) - Aux Percussion", thumbnail_url: thumb)

      described_class.perform_now

      expect(conductor.reload.is_group_representative).to be true
      expect(part.reload.is_group_representative).to be_falsey
    end

    it "breaks ties alphabetically among same-tier parts" do
      # Create the alphabetically-later row FIRST so insertion (rowid) order diverges from
      # title order — otherwise the test would pass even if the title tiebreak were dropped.
      trombone = create(:score, :smd, title: "Birds of a Feather (arr. Larry Moore) - Trombone 2", thumbnail_url: thumb)
      aux = create(:score, :smd, title: "Birds of a Feather (arr. Larry Moore) - Aux Percussion", thumbnail_url: thumb)

      described_class.perform_now

      expect(aux.reload.is_group_representative).to be true
      expect(trombone.reload.is_group_representative).to be_falsey
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

      expect(stats).to eq(part_keys: 1, bundle_keys: 0, representatives: 1)
    end
  end
end
