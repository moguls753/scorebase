# frozen_string_literal: true

require "rails_helper"

RSpec.describe Stretta::Client do
  let(:client) { described_class.new(logger: Logger.new(nil)) }
  let(:endpoint) { described_class::ENDPOINT }

  before { allow(client).to receive(:sleep) }

  def graphql_body(data:, errors: nil)
    { data: data, errors: errors }.compact.to_json
  end

  describe "#products" do
    it "yields nothing for a handle the API doesn't know, with a single request" do
      stub_request(:post, endpoint)
        .to_return(status: 200, body: graphql_body(data: { "p0" => nil }))

      result = client.products([ "gone" ]).to_a

      expect(result).to eq([])
      expect(WebMock).to have_requested(:post, endpoint).times(1)
    end

    # A batch-wide failure comes back shaped as {"p0"=>nil, "p1"=>nil, ...} plus an
    # errors array — a Hash#blank? check alone misses it (a Hash with nil values
    # isn't blank), which used to make this look identical to "both products
    # confirmed absent" instead of "the batch failed".
    it "retries a batch-wide failure instead of treating every handle as absent" do
      stub_request(:post, endpoint)
        .to_return(status: 200, body: graphql_body(data: { "p0" => nil, "p1" => nil },
                                                     errors: [ { "message" => "throttled" } ]))

      result = client.products([ "a", "b" ]).to_a

      expect(result).to eq([])
      expect(WebMock).to have_requested(:post, endpoint).times(described_class::MAX_ATTEMPTS)
    end

    it "yields real products alongside a null alias in the same batch" do
      stub_request(:post, endpoint)
        .to_return(status: 200, body: graphql_body(data: { "p0" => { "handle" => "kept" }, "p1" => nil }))

      result = client.products([ "kept", "gone" ]).to_a

      expect(result.map { |product| product[:handle] }).to eq([ "kept" ])
    end

    # A run of failed batches means the shop is down or the token rotated, not that
    # a run of products vanished at once — continuing would write a thinned catalogue.
    it "aborts once too many batches in a row fail" do
      small_batches = described_class.new(batch_size: 2, logger: Logger.new(nil))
      allow(small_batches).to receive(:sleep)
      stub_request(:post, endpoint)
        .to_return(status: 200, body: graphql_body(data: { "p0" => nil, "p1" => nil },
                                                     errors: [ { "message" => "throttled" } ]))
      handles = (1..described_class::MAX_CONSECUTIVE_FAILURES * 2).map(&:to_s)

      expect { small_batches.products(handles).to_a }.to raise_error(Stretta::Client::Aborted)
    end
  end
end
