# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmdRefreshJob do
  let(:crawler) { instance_double(SmdCrawler::Crawler) }

  before do
    allow(SmdCrawler::Crawler).to receive(:new).and_return(crawler)
    allow(crawler).to receive(:crawl_product).and_return({ success: true, metadata: { external_id: "1" } })
    allow(crawler).to receive(:save_product)
  end

  def smd_score(external_id:, last_crawled_at: nil, **attrs)
    Score.create!(source: "smd", external_id: external_id, title: "T#{external_id}",
                  last_crawled_at: last_crawled_at, **attrs)
  end

  it "refreshes never-crawled scores before previously-crawled ones" do
    smd_score(external_id: "old", last_crawled_at: 2.days.ago)
    smd_score(external_id: "never")

    described_class.new.perform(limit: 1)

    expect(crawler).to have_received(:crawl_product).with("never")
  end

  it "refreshes the stalest crawled score first" do
    smd_score(external_id: "recent", last_crawled_at: 1.hour.ago)
    smd_score(external_id: "stale", last_crawled_at: 30.days.ago)

    described_class.new.perform(limit: 1)

    expect(crawler).to have_received(:crawl_product).with("stale")
  end

  it "advances across runs instead of redoing the same rows" do
    smd_score(external_id: "a")
    smd_score(external_id: "b")
    allow(crawler).to receive(:save_product) { |m| Score.find_by(external_id: m[:external_id]).touch(:last_crawled_at) }
    allow(crawler).to receive(:crawl_product) { |id| { success: true, metadata: { external_id: id } } }

    described_class.new.perform(limit: 1)
    described_class.new.perform(limit: 1)

    expect(crawler).to have_received(:crawl_product).with("a").once
    expect(crawler).to have_received(:crawl_product).with("b").once
  end

  it "limits to group representatives when scoped" do
    smd_score(external_id: "plain")
    smd_score(external_id: "rep", is_group_representative: true)

    described_class.new.perform(limit: 10, scope: :representatives)

    expect(crawler).to have_received(:crawl_product).with("rep")
    expect(crawler).not_to have_received(:crawl_product).with("plain")
  end

  it "skips soft-deleted and non-SMD scores" do
    smd_score(external_id: "gone", deleted_at: Time.current)
    Score.create!(source: "imslp", external_id: "imslp1", title: "Free")

    stats = described_class.new.perform(limit: 10)

    expect(stats[:examined]).to eq(0)
  end

  it "stamps last_crawled_at on failure so a broken row cannot block the queue" do
    score = smd_score(external_id: "broken")
    allow(crawler).to receive(:crawl_product).and_return({ success: false, error: "not_found" })

    stats = described_class.new.perform(limit: 10)

    expect(stats[:failed]).to eq(1)
    expect(score.reload.last_crawled_at).to be_present
  end

  it "rejects an unknown scope" do
    expect { described_class.new.perform(scope: :bogus) }.to raise_error(ArgumentError, /Invalid scope/)
  end

  # recurring.yml is YAML, so the scheduled runs hand us a String, not a Symbol.
  it "accepts a string scope, as the recurring schedule supplies it" do
    smd_score(external_id: "plain")
    smd_score(external_id: "rep", is_group_representative: true)

    described_class.new.perform(limit: 10, scope: "representatives")

    expect(crawler).to have_received(:crawl_product).with("rep")
    expect(crawler).not_to have_received(:crawl_product).with("plain")
  end
end
