# frozen_string_literal: true

require "rails_helper"

RSpec.describe Stretta::Importer do
  def product(handle: "148059", **overrides)
    { handle: handle, title: "Großer Gott", vendor: "Carus Verlag", itemtype: "Partitur",
      instrument: "Orgel", slug_de: "grosser-gott-nr-#{handle}", price: 5.5,
      available_for_sale: true, product_type: "physical",
      authors: [{ role: "author", name: "Hans Leitner", slug: "hans-leitner" }] }.merge(overrides)
  end

  it "writes an accepted product and skips a rejected one" do
    stats = described_class.new.import([product, product(handle: "2", itemtype: "CD")])

    expect(Score.where(source: "stretta").pluck(:external_id)).to eq(["148059"])
    expect(stats).to include(allowlist: 1, denylist: 1, written: 1)
  end

  # The columns another job owns. Without this the sync writes back the raw name
  # that NormalizeComposersJob canonicalised the night before, and the row drops off
  # its hub and into the LLM queue — every single day.
  it "never overwrites what a downstream job owns" do
    described_class.new.import([product])
    score = Score.find_by!(source: "stretta", external_id: "148059")
    score.update_columns(composer: "Leitner, Hans", composer_status: "normalized",
                         pedagogical_grade: "Grade 5", is_group_representative: true,
                         group_key: "hand-set")

    described_class.new.import([product(price: 6.5)])

    expect(score.reload).to have_attributes(
      composer: "Leitner, Hans", composer_status: "normalized",
      pedagogical_grade: "Grade 5", is_group_representative: true,
      group_key: "hand-set", price_eur: 6.5
    )
  end

  # Nothing else writes these, so a re-import may as well carry an improved mapping
  # table — otherwise the only way to apply one is to refetch the whole catalogue.
  it "refreshes what only the mapper derives" do
    described_class.new.import([product])
    score = Score.find_by!(source: "stretta", external_id: "148059")
    score.update_columns(instruments: "stale", smd_category: "stale", group_rank: 99)

    described_class.new.import([product])

    expect(score.reload).to have_attributes(instruments: "Organ", smd_category: nil, group_rank: 10)
  end

  # deleted_at is out of UPDATABLE on purpose: an admin's soft-delete (Avo's delete
  # button calls soft_delete!) must survive the next sync, and the importer has no
  # way to tell that apart from StrettaDisappearanceJob's own deletions. Both now
  # wait for a deliberate restore instead of silently reappearing.
  it "leaves a soft-deleted row deleted, even once the product is fetchable again" do
    described_class.new.import([product])
    score = Score.find_by!(source: "stretta", external_id: "148059")
    score.soft_delete!

    described_class.new.import([product])

    expect(score.reload.deleted_at).not_to be_nil
  end

  # SQLite refuses the whole statement: "ON CONFLICT DO UPDATE command does not
  # affect row a second time".
  it "survives the same handle appearing twice in one batch" do
    expect { described_class.new.import([product, product]) }.not_to raise_error
    expect(Score.where(source: "stretta").count).to eq(1)
  end
end
