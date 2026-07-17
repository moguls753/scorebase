# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/middleware/sitemap_cache_control")

RSpec.describe SitemapCacheControl do
  def call(path, upstream_headers)
    app = ->(_env) { [ 200, upstream_headers.dup, [ "body" ] ] }
    described_class.new(app).call("PATH_INFO" => path)
  end

  it "shortens Cache-Control for the sitemap and its indexed children" do
    [ "/sitemap.xml.gz", "/sitemap1.xml.gz", "/sitemap.xml" ].each do |path|
      _status, headers, _body = call(path, "Cache-Control" => "public, max-age=31556952")
      expect(headers["cache-control"]).to eq("public, max-age=3600")
      expect(headers).not_to have_key("Cache-Control")
    end
  end

  it "overrides regardless of the upstream header case (Rack serves lowercase)" do
    _status, headers, _body = call("/sitemap.xml.gz", "cache-control" => "public, max-age=31556952")

    expect(headers["cache-control"]).to eq("public, max-age=3600")
  end

  it "leaves digest-stamped assets on the long TTL" do
    _status, headers, _body = call("/assets/application-abc123.js", "Cache-Control" => "public, max-age=31556952")

    expect(headers["Cache-Control"]).to eq("public, max-age=31556952")
    expect(headers).not_to have_key("cache-control")
  end
end
