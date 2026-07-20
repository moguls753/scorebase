# frozen_string_literal: true

require "net/http"
require "json"

module SmdCrawler
  # Cloudflare validates cf_clearance against the User-Agent that solved it, so
  # both must be replayed together. Solving costs a browser render, hence once.
  class Clearance
    # The bypass geolocates to Germany; without this we store EUR prices and
    # German category names that miss HubDataBuilder's English allowlist.
    LOCALE_COOKIE = "currency=USD&remembered=False&lastculture=en-US&lastsite=Global&usertype=0"
    SEED_URL = "https://www.sheetmusicdirect.com/se/ID_No/1000001/Product.aspx"
    DEFAULT_BYPASS_URL = "http://localhost:8000"
    ACQUIRE_TIMEOUT = 180

    # Disables clearance without changing call sites; falls back to bare requests.
    class Null
      def user_agent = nil
      def cookie_header = nil
      def ensure! = false
      def refresh! = false
    end

    attr_reader :user_agent, :cookie_header

    def initialize(bypass_url: nil, seed_url: SEED_URL, timeout: ACQUIRE_TIMEOUT)
      @bypass_url = bypass_url || ENV.fetch("CLOUDFLARE_BYPASS_URL", DEFAULT_BYPASS_URL)
      @seed_url = seed_url
      @timeout = timeout
    end

    def ensure!
      return true if @cookie_header

      refresh!
    end

    def refresh!
      @cookie_header = nil # ensure! only checks presence; a stale one would stick

      payload = solve
      cookies = payload && payload["cookies"]
      return false if cookies.nil? || cookies.empty?

      @user_agent = payload["user_agent"]
      @cookie_header = cookies.merge("cuser" => LOCALE_COOKIE)
                              .map { |name, value| "#{name}=#{value}" }
                              .join("; ")
      true
    end

    private

    def solve
      uri = URI("#{@bypass_url}/cookies")
      uri.query = URI.encode_www_form(url: @seed_url)

      response = Net::HTTP.start(uri.host, uri.port, open_timeout: 10, read_timeout: @timeout) do |http|
        http.request(Net::HTTP::Get.new(uri))
      end
      return nil unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue StandardError => e
      Rails.logger.warn("[SmdCrawler::Clearance] acquire failed: #{e.class}: #{e.message}")
      nil
    end
  end
end
