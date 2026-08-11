# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmdCrawlJob do
  let(:crawler) { instance_double(SmdCrawler::Crawler) }

  before do
    allow(SmdCrawler::Crawler).to receive(:new).and_return(crawler)
    allow(crawler).to receive(:crawl_index).and_return({ saved: 0 })
  end

  # recurring.yml is YAML, so the scheduled run hands us a String, not a Symbol.
  it "accepts a string mode, as the recurring schedule supplies it" do
    described_class.new.perform(limit: 1000, mode: "import")

    expect(crawler).to have_received(:crawl_index)
      .with(a_string_including("sitemap-index-prod-hl"), product_limit: 1000, mode: :import)
  end
end
