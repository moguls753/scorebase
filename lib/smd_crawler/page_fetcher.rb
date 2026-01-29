# frozen_string_literal: true

require "net/http"
require "uri"

module SmdCrawler
  class PageFetcher
    USER_AGENT = "ScoreBase/1.0 (sheet music search engine; +https://scorebase.org)"
    DEFAULT_TIMEOUT = 30
    DEFAULT_MAX_RETRIES = 3
    DEFAULT_DELAY_RANGE = 0.5..1.5

    def initialize(delay_range: DEFAULT_DELAY_RANGE, max_retries: DEFAULT_MAX_RETRIES, timeout: DEFAULT_TIMEOUT)
      @delay_range = delay_range
      @max_retries = max_retries
      @timeout = timeout
      @last_request_at = nil
    end

    def fetch(url)
      respect_rate_limit

      attempts = 0
      last_error = nil
      result = nil

      while attempts < @max_retries
        attempts += 1

        begin
          result = make_request(url)

          case result[:status]
          when 200
            return { success: true, body: result[:body], status: 200 }
          when 404
            return { success: false, status: 404, error: "not_found" }
          when 429
            # Rate limited - back off longer
            sleep(2 ** attempts)
            last_error = "rate_limited"
          when 500..599
            # Server error - retry with backoff
            sleep(0.1 * (2 ** attempts)) if attempts < @max_retries
            last_error = "server_error"
          else
            last_error = "http_#{result[:status]}"
          end
        rescue Net::OpenTimeout, Net::ReadTimeout
          last_error = "timeout"
          sleep(0.1 * (2 ** attempts)) if attempts < @max_retries
        rescue Errno::ECONNRESET, Errno::ECONNREFUSED, SocketError => e
          last_error = "network_error"
          sleep(0.1 * (2 ** attempts)) if attempts < @max_retries
        end
      end

      { success: false, status: result&.dig(:status), error: last_error }
    end

    private

    def respect_rate_limit
      return unless @last_request_at

      elapsed = Time.now - @last_request_at
      delay = rand(@delay_range)
      sleep(delay - elapsed) if elapsed < delay
    end

    def make_request(url)
      uri = URI(url)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = @timeout
      http.read_timeout = @timeout
      # Use VERIFY_NONE as a workaround for CRL checking issues
      # SMD's certificate has a CRL endpoint that Ruby's OpenSSL can't reach on some networks
      # The connection is still encrypted, just certificate revocation isn't checked
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE

      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = USER_AGENT

      @last_request_at = Time.now
      response = http.request(request)

      # Force UTF-8 encoding - SMD pages are UTF-8 but Net::HTTP returns ASCII-8BIT
      body = response.body&.dup&.force_encoding("UTF-8")

      { status: response.code.to_i, body: body }
    end
  end
end
