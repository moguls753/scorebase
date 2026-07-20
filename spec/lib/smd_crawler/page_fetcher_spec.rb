# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe SmdCrawler::PageFetcher do
  # No delay for tests; Null clearance keeps the bypass out of the unit specs.
  let(:clearance) { SmdCrawler::Clearance::Null.new }
  let(:fetcher) { described_class.new(delay_range: 0..0, clearance: clearance) }

  describe "#fetch" do
    let(:url) { "https://www.sheetmusicdirect.com/se/ID_No/123/Product.aspx" }

    it "returns HTML on success" do
      stub_request(:get, url)
        .to_return(status: 200, body: "<html>test</html>")

      result = fetcher.fetch(url)

      expect(result[:success]).to be true
      expect(result[:body]).to eq("<html>test</html>")
      expect(result[:status]).to eq(200)
    end

    it "sends correct User-Agent header" do
      stub_request(:get, url)
        .with(headers: { "User-Agent" => /ScoreBase/ })
        .to_return(status: 200, body: "ok")

      fetcher.fetch(url)

      expect(WebMock).to have_requested(:get, url)
        .with(headers: { "User-Agent" => "ScoreBase/1.0 (sheet music search engine; +https://scorebase.org)" })
    end

    it "returns failure for 404" do
      stub_request(:get, url).to_return(status: 404)

      result = fetcher.fetch(url)

      expect(result[:success]).to be false
      expect(result[:status]).to eq(404)
      expect(result[:error]).to eq("not_found")
    end

    it "retries on 5xx errors" do
      stub_request(:get, url)
        .to_return(status: 500)
        .then.to_return(status: 200, body: "ok")

      result = fetcher.fetch(url)

      expect(result[:success]).to be true
      expect(WebMock).to have_requested(:get, url).times(2)
    end

    it "gives up after max retries" do
      stub_request(:get, url).to_return(status: 500)

      result = fetcher.fetch(url)

      expect(result[:success]).to be false
      expect(result[:error]).to eq("server_error")
      expect(WebMock).to have_requested(:get, url).times(3) # Default max_retries
    end

    it "retries on network errors" do
      stub_request(:get, url)
        .to_raise(Errno::ECONNRESET)
        .then.to_return(status: 200, body: "ok")

      result = fetcher.fetch(url)

      expect(result[:success]).to be true
    end

    it "handles timeout errors" do
      stub_request(:get, url).to_timeout

      result = fetcher.fetch(url)

      expect(result[:success]).to be false
      expect(result[:error]).to eq("timeout")
    end
  end

  describe "cloudflare clearance" do
    let(:url) { "https://www.sheetmusicdirect.com/se/ID_No/123/Product.aspx" }
    let(:clearance) do
      instance_double(SmdCrawler::Clearance, ensure!: true, refresh!: true,
                                             user_agent: "Mozilla/5.0 (X11; Ubuntu) Firefox/140.0",
                                             cookie_header: "cf_clearance=abc; cuser=currency=USD")
    end

    it "replays the solved User-Agent and cookies together" do
      stub_request(:get, url).to_return(status: 200, body: "ok")

      fetcher.fetch(url)

      expect(WebMock).to have_requested(:get, url).with(headers: {
        "User-Agent" => "Mozilla/5.0 (X11; Ubuntu) Firefox/140.0",
        "Cookie" => "cf_clearance=abc; cuser=currency=USD"
      })
    end

    it "re-solves clearance and retries on 403" do
      stub_request(:get, url)
        .to_return(status: 403)
        .then.to_return(status: 200, body: "ok")

      result = fetcher.fetch(url)

      expect(result[:success]).to be true
      expect(clearance).to have_received(:refresh!)
    end

    it "reports a cloudflare challenge when clearance never succeeds" do
      stub_request(:get, url).to_return(status: 403)

      result = fetcher.fetch(url)

      expect(result[:success]).to be false
      expect(result[:error]).to eq("cloudflare_challenge")
    end
  end

  describe "rate limiting" do
    it "respects delay between requests" do
      url1 = "https://www.sheetmusicdirect.com/se/ID_No/1/Product.aspx"
      url2 = "https://www.sheetmusicdirect.com/se/ID_No/2/Product.aspx"

      stub_request(:get, url1).to_return(status: 200, body: "1")
      stub_request(:get, url2).to_return(status: 200, body: "2")

      fetcher_with_delay = described_class.new(delay_range: 0.1..0.1, clearance: clearance)

      start = Time.now
      fetcher_with_delay.fetch(url1)
      fetcher_with_delay.fetch(url2)
      elapsed = Time.now - start

      expect(elapsed).to be >= 0.1
    end
  end
end
