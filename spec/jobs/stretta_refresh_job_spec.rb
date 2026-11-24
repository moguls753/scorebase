# frozen_string_literal: true

require "rails_helper"

RSpec.describe StrettaRefreshJob do
  let(:client) { Stretta::Client.new(batch_size: 1) }
  let(:endpoint) { Stretta::Client::ENDPOINT }

  it "refreshes prices and publisher metadata from the same response without touching unrelated metadata" do
    score = create(:score, :stretta, stretta_metadata: { content: "Old list", preview_pdfs: ["one.pdf"], ismn: "keep" })
    node = { handle: score.external_id, availableForSale: true, priceRange: { minVariantPrice: { amount: "15.00" } },
             texts: { value: { content: "New list" }.to_json }, previewPdfs: nil }
    request = stub_request(:post, endpoint).to_return(body: { data: { p0: node } }.to_json)
    stats = described_class.new.perform(client: client)

    expect(request).to have_been_requested.once
    expect(stats).to include(checked: 1, updated: 1, metadata_changed: 1)
    expect(score.reload.stretta_metadata).to eq("content" => "New list", "ismn" => "keep")
    expect(score.price_eur).to eq(15)
    travel_to(1.day.from_now) do
      expect { described_class.new.perform(client: client) }.not_to change { score.reload.updated_at }
    end
  end

  it "rotates confirmed misses but leaves failed batches eligible for the next refresh" do
    failed = create(:score, :stretta, stretta_metadata: { description: "keep" })
    missing = create(:score, :stretta)
    stub_request(:post, endpoint).to_return(body: { data: { p0: nil } }.to_json)
    stub_request(:post, endpoint).with { |req| JSON.parse(req.body)["query"].include?(failed.external_id.to_json) }
                                 .to_return(body: { data: { p0: nil }, errors: [{ message: "throttled" }] }.to_json)
    allow(client).to receive(:sleep)

    stats = described_class.new.perform(client: client)
    expect(stats).to include(checked: 0, missing: 1, failed: 1, metadata_changed: 0)
    expect(failed.reload).to have_attributes(stretta_metadata: { "description" => "keep" }, last_crawled_at: nil)
    expect(missing.reload.last_crawled_at).to be_present
  end
end
