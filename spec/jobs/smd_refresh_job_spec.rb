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

  def max_failures
    SmdCrawler::Crawler::MAX_CONSECUTIVE_FAILURES
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

  it "prefers an ungrouped row over a grouped one when neither was ever crawled" do
    smd_score(external_id: "member", group_key: "g1")
    smd_score(external_id: "ungrouped")

    described_class.new.perform(limit: 1)

    expect(crawler).to have_received(:crawl_product).with("ungrouped")
  end

  # The tie-break must not outrank staleness, or grouped rows would never be revisited.
  it "still prefers a stale grouped row over a fresh ungrouped one" do
    smd_score(external_id: "fresh_ungrouped", last_crawled_at: 1.hour.ago)
    smd_score(external_id: "stale_member", group_key: "g1", last_crawled_at: 30.days.ago)

    described_class.new.perform(limit: 1)

    expect(crawler).to have_received(:crawl_product).with("stale_member")
  end

  it "advances across runs instead of redoing the same rows" do
    smd_score(external_id: "a")
    smd_score(external_id: "b")

    described_class.new.perform(limit: 1)
    described_class.new.perform(limit: 1)

    expect(crawler).to have_received(:crawl_product).with("a").once
    expect(crawler).to have_received(:crawl_product).with("b").once
  end

  # SMD redirects discontinued products to a replacement, so the mpn in the
  # response can differ from the id we asked for. save_product then updates a
  # different row; if that were the only thing stamping progress, the requested
  # row would sit at the head of the queue and be re-crawled on every run forever.
  it "stamps the row it asked for even when the response describes another product" do
    score = smd_score(external_id: "requested")
    smd_score(external_id: "replacement", last_crawled_at: 1.year.ago)
    allow(crawler).to receive(:crawl_product)
      .and_return({ success: true, metadata: { external_id: "replacement" } })

    described_class.new.perform(limit: 1)

    expect(score.reload.last_crawled_at).to be_present
  end

  it "aborts a run that is failing continuously rather than burning the whole limit" do
    (max_failures + 10).times { |i| smd_score(external_id: "s#{i}") }
    allow(crawler).to receive(:crawl_product).and_return({ success: false, error: "cloudflare_challenge" })

    stats = described_class.new.perform(limit: 500)

    expect(stats[:aborted]).to be true
    expect(stats[:examined]).to eq(max_failures)
  end

  it "keeps refreshing past a run of 404s, which say nothing about our access to SMD" do
    (max_failures + 10).times { |i| smd_score(external_id: "s#{i}") }
    allow(crawler).to receive(:crawl_product).and_return({ success: false, error: "not_found" })

    stats = described_class.new.perform(limit: 500)

    expect(stats[:aborted]).to be false
    expect(stats[:examined]).to eq(max_failures + 10)
  end

  # Two streaks that would abort if concatenated, split by one success.
  it "resets the failure streak after a success" do
    streak = max_failures - 1
    streak.times { |i| smd_score(external_id: "a#{i}", last_crawled_at: (100 - i).days.ago) }
    smd_score(external_id: "good", last_crawled_at: (100 - streak).days.ago)
    streak.times { |i| smd_score(external_id: "b#{i}", last_crawled_at: (99 - streak - i).days.ago) }
    allow(crawler).to receive(:crawl_product).and_return({ success: false, error: "cloudflare_challenge" })
    allow(crawler).to receive(:crawl_product).with("good").and_return({ success: true, metadata: { external_id: "good" } })

    stats = described_class.new.perform(limit: 500)

    expect(stats[:aborted]).to be false
    expect(stats[:examined]).to eq(streak * 2 + 1)
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

  it "counts a response that describes a different product than the one requested" do
    smd_score(external_id: "requested")
    allow(crawler).to receive(:crawl_product)
      .and_return({ success: true, metadata: { external_id: "replacement" } })

    stats = described_class.new.perform(limit: 1)

    expect(stats[:replaced]).to eq(1)
  end

  it "tallies failures by error string so a 404 can be told apart from a Cloudflare block" do
    smd_score(external_id: "a")
    smd_score(external_id: "b")
    allow(crawler).to receive(:crawl_product).with("a").and_return({ success: false, error: "not_found" })
    allow(crawler).to receive(:crawl_product).with("b").and_return({ success: false, error: "unparseable" })

    stats = described_class.new.perform(limit: 10)

    expect(stats[:errors]).to eq({ "not_found" => 1, "unparseable" => 1 })
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
