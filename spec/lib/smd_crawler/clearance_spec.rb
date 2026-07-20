# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe SmdCrawler::Clearance do
  subject(:clearance) { described_class.new(bypass_url: bypass_url, seed_url: seed_url) }

  let(:bypass_url) { "http://bypass.test:8000" }
  let(:seed_url) { "https://www.sheetmusicdirect.com/se/ID_No/1/Product.aspx" }
  let(:cookies_endpoint) { "#{bypass_url}/cookies?url=#{CGI.escape(seed_url)}" }

  def stub_bypass(cookies:, user_agent: "Mozilla/5.0 Firefox/140.0")
    stub_request(:get, cookies_endpoint)
      .to_return(status: 200, body: { cookies: cookies, user_agent: user_agent }.to_json)
  end

  it "builds a cookie header from the solved cookies" do
    stub_bypass(cookies: { "cf_clearance" => "xyz", "ASP.NET_SessionId" => "abc" })

    expect(clearance.ensure!).to be true
    expect(clearance.cookie_header).to include("cf_clearance=xyz", "ASP.NET_SessionId=abc")
  end

  it "exposes the User-Agent that solved the challenge" do
    stub_bypass(cookies: { "cf_clearance" => "xyz" }, user_agent: "Mozilla/5.0 Firefox/140.0")

    clearance.ensure!

    expect(clearance.user_agent).to eq("Mozilla/5.0 Firefox/140.0")
  end

  it "overrides the storefront cookie to the US locale" do
    stub_bypass(cookies: { "cf_clearance" => "xyz", "cuser" => "currency=EUR&lastculture=de-DE" })

    clearance.ensure!

    expect(clearance.cookie_header).to include("cuser=#{described_class::LOCALE_COOKIE}")
    expect(clearance.cookie_header).not_to include("de-DE")
  end

  it "solves once and reuses the result" do
    stub_bypass(cookies: { "cf_clearance" => "xyz" })

    clearance.ensure!
    clearance.ensure!

    expect(WebMock).to have_requested(:get, cookies_endpoint).once
  end

  it "re-solves on refresh" do
    stub_bypass(cookies: { "cf_clearance" => "xyz" })

    clearance.ensure!
    clearance.refresh!

    expect(WebMock).to have_requested(:get, cookies_endpoint).twice
  end

  it "fails soft when the bypass is unreachable" do
    stub_request(:get, cookies_endpoint).to_raise(Errno::ECONNREFUSED)

    expect(clearance.ensure!).to be false
    expect(clearance.cookie_header).to be_nil
  end

  it "fails soft when the bypass returns no cookies" do
    stub_bypass(cookies: {})

    expect(clearance.ensure!).to be false
  end

  describe described_class::Null do
    it "reports no clearance so callers fall back to bare requests" do
      null = described_class.new

      expect(null.ensure!).to be false
      expect(null.cookie_header).to be_nil
      expect(null.user_agent).to be_nil
    end
  end
end
