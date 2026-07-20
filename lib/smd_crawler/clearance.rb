# frozen_string_literal: true

require "net/http"
require "json"

module SmdCrawler
  # Cloudflare clearance for sheetmusicdirect.com.
  #
  # SMD became Cloudflare-gated after the original import; plain requests now
  # get 403 from datacenter IPs. The bypass accessory solves the challenge in a
  # real browser and returns the cf_clearance cookie together with the exact
  # User-Agent it used. Cloudflare validates the two as a pair, so both must be
  # replayed on every request or the clearance is rejected.
  #
  # The bypass renders a full browser page per call (tens of seconds), so it is
  # used only to mint clearance — the crawl itself then runs over plain HTTP.
  class Clearance
    # SMD serves currency and language off this cookie, keyed to the requesting
    # IP. The bypass container geolocates to Germany, which yields EUR prices,
    # German titles and German category_level_2 values (e.g. "Klavier solo"
    # instead of "Piano Solo") that miss HubDataBuilder's English allowlist.
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
