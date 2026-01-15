# frozen_string_literal: true

require "net/http"

# HTTP client that proxies requests through CloudflareBypass to handle
# Cloudflare-protected sites. Works for both API requests and binary downloads.
#
# Usage:
#   client = CloudflareBypassClient.new
#   response = client.get("https://www.cpdl.org/wiki/api.php?action=query")
#   response.body  # => JSON or binary data
#
# Configure via ENV:
#   CLOUDFLARE_BYPASS_URL=http://localhost:8000
#
class CloudflareBypassClient
  class Error < StandardError; end

  DEFAULT_URL = "http://localhost:8000"

  def initialize(base_url: nil)
    @base_url = base_url || ENV.fetch("CLOUDFLARE_BYPASS_URL", DEFAULT_URL)
  end

  def self.available?
    new.available?
  end

  def available?
    uri = URI("#{@base_url}/cookies?url=https://example.com")
    Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: 10) do |http|
      http.get(uri.request_uri).is_a?(Net::HTTPSuccess)
    end
  rescue StandardError
    false
  end

  # GET request through the bypass proxy
  # Returns Net::HTTPResponse
  def get(url, timeout: 120)
    uri = URI(url)
    proxy_uri = build_proxy_uri(uri)

    Net::HTTP.start(proxy_uri.host, proxy_uri.port, open_timeout: 10, read_timeout: timeout) do |http|
      request = Net::HTTP::Get.new(proxy_uri)
      request["x-hostname"] = uri.host
      http.request(request)
    end
  end

  # Download a file through the bypass proxy
  # Returns response body as binary string
  def download(url, timeout: 120)
    response = get(url, timeout: timeout)

    unless response.is_a?(Net::HTTPSuccess)
      raise Error, "Download failed: HTTP #{response.code}"
    end

    response.body
  end

  private

  def build_proxy_uri(original_uri)
    path = original_uri.path
    path += "?#{original_uri.query}" if original_uri.query
    URI("#{@base_url}#{path}")
  end
end
