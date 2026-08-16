# frozen_string_literal: true

require "rails_helper"

RSpec.describe StrettaDisappearanceJob do
  def fake_harvester(live)
    instance_double(Stretta::SitemapHarvester).tap do |harvester|
      allow(harvester).to receive(:each_handle) { |&block| live.each(&block) }
    end
  end

  def fake_client(answers)
    instance_double(Stretta::Client).tap do |client|
      allow(client).to receive(:products) do |suspects|
        suspects.select { |handle| answers.include?(handle) }.map { |handle| { handle: handle } }
      end
    end
  end

  def padding(count)
    create_list(:score, count, :stretta).map(&:external_id)
  end

  it "soft-deletes a held row that is off the sitemap and unreachable via the API" do
    live = padding(99)
    gone = create(:score, :stretta)

    stats = described_class.new.perform(client: fake_client([]), harvester: fake_harvester(live))

    expect(gone.reload.deleted_at).to be_present
    expect(stats).to include(held: 100, suspects: 1, deleted: 1)
  end

  # 8.2% of sitemap ids are dead while the product still sells — absence from the
  # sitemap alone must never be enough to delete.
  it "keeps a row the sitemap misses but the API still answers for" do
    live = padding(99)
    still_sells = create(:score, :stretta)

    described_class.new.perform(client: fake_client([ still_sells.external_id ]), harvester: fake_harvester(live))

    expect(still_sells.reload.deleted_at).to be_nil
  end

  it "never treats a row the sitemap lists as live as a suspect" do
    on_sitemap = create(:score, :stretta)
    live = padding(99) + [ on_sitemap.external_id ]

    described_class.new.perform(client: fake_client([]), harvester: fake_harvester(live))

    expect(on_sitemap.reload.deleted_at).to be_nil
  end

  # A run that would remove more than 1% of held rows is a broken harvest, not a
  # shrinking catalogue — refuse rather than empty the shelf.
  it "refuses to delete when confirmed suspects exceed the guard share" do
    live = padding(95)
    gone = create_list(:score, 5, :stretta)

    expect {
      described_class.new.perform(client: fake_client([]), harvester: fake_harvester(live))
    }.to raise_error(described_class::TooManyDeletions)

    expect(gone.map { |score| score.reload.deleted_at }).to all(be_nil)
  end
end
