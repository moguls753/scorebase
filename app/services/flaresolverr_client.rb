# frozen_string_literal: true

require "net/http"
require "json"

# HTTP client that proxies requests through FlareSolverr to handle
# Cloudflare-protected sites. Better for API requests due to configurable timeout.
#
# Usage:
#   client = FlaresolverrClient.new
#   response = client.get("https://www.cpdl.org/wiki/api.php?action=query")
#   response.body  # => response content
#   response.code  # => HTTP status code
#
# Configure via ENV:
#   FLARESOLVERR_URL=http://localhost:8191
#
# FlareSolverr API:
#   POST /v1 with JSON body: {"cmd": "request.get", "url": "...", "maxTimeout": 60000}
#   Returns JSON with solution.response containing page content
#
class FlaresolverrClient
  class Error < StandardError; end

  DEFAULT_URL = "http://localhost:8191"
  DEFAULT_TIMEOUT = 60_000  # 60 seconds in milliseconds

  def initialize(base_url: nil, max_timeout: nil, session: "scorebase")
    @base_url = base_url || ENV.fetch("FLARESOLVERR_URL", DEFAULT_URL)
    @max_timeout = max_timeout || ENV.fetch("FLARESOLVERR_TIMEOUT", DEFAULT_TIMEOUT).to_i
    @session = session  # Persist cookies across requests (solves challenge once)
  end

  def self.available?
    new.available?
  end

  def available?
    uri = URI("#{@base_url}/health")
    response = Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: 10) do |http|
      http.get(uri.request_uri)
    end
    response.is_a?(Net::HTTPSuccess)
  rescue StandardError
    false
  end

  # GET request through FlareSolverr proxy
  # Returns a response-like object with body and code
  def get(url, timeout: nil)
    request_timeout = timeout || @max_timeout
    uri = URI("#{@base_url}/v1")

    payload = {
      cmd: "request.get",
      url: url,
      maxTimeout: request_timeout,
      session: @session
    }

    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 10
    # Ruby timeout should be longer than FlareSolverr timeout
    http.read_timeout = (request_timeout / 1000.0).ceil + 30

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = payload.to_json

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      raise Error, "FlareSolverr request failed: HTTP #{response.code}"
    end

    parse_response(response.body)
  rescue Errno::ECONNREFUSED
    raise Error, "FlareSolverr not running at #{@base_url}"
  rescue Net::OpenTimeout
    raise Error, "FlareSolverr connection timeout"
  rescue Net::ReadTimeout
    raise Error, "FlareSolverr read timeout (request took longer than #{request_timeout}ms)"
  rescue JSON::ParserError => e
    raise Error, "Failed to parse FlareSolverr response: #{e.message}"
  end

  private

  # Parse FlareSolverr JSON response and return a response-like object
  def parse_response(body)
    data = JSON.parse(body)

    status = data["status"]
    unless status == "ok"
      message = data["message"] || "Unknown error"
      raise Error, "FlareSolverr error: #{message}"
    end

    solution = data["solution"]
    unless solution
      raise Error, "FlareSolverr returned no solution"
    end

    FlareSolverrResponse.new(
      body: unwrap_browser_json(solution["response"]),
      code: solution["status"].to_s,
      url: solution["url"],
      cookies: solution["cookies"]
    )
  end

  # Chrome wraps JSON responses in HTML for display:
  #   <html>...<pre>{"actual":"json"}</pre>...</html>
  # Extract the raw JSON from within <pre> tags
  def unwrap_browser_json(content)
    return content unless content&.start_with?("<html>", "<!DOCTYPE", "<HTML")

    if match = content.match(%r{<pre[^>]*>(.+?)</pre>}m)
      match[1]
    else
      content
    end
  end

  # Response object that mimics Net::HTTPResponse interface
  class FlareSolverrResponse
    attr_reader :body, :code, :url, :cookies

    def initialize(body:, code:, url:, cookies:)
      @body = body
      @code = code
      @url = url
      @cookies = cookies
    end

    def success?
      code.to_i.between?(200, 299)
    end
  end
end
