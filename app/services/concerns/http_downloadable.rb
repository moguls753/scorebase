# Shared HTTP download functionality for ThumbnailGenerator and PdfSyncer
require "cgi"
require "net/http"
require "uri"
require "openssl"

module HttpDownloadable
  extend ActiveSupport::Concern

  MAX_RETRIES = 3
  RETRY_DELAY = 2  # seconds, doubles each retry
  IMSLP_RATE_LIMIT = 3  # seconds between IMSLP requests to avoid IP bans
  CLOUDFLARE_PROTECTED_HOSTS = %w[cpdl.org www.cpdl.org].freeze

  private

  def http_download(url, destination, redirect_limit: 10, timeout: 30, retries: 0)
    # IMSLP requires special handling - their download page contains the real CDN URL
    if url.include?("imslp.org/wiki/Special:IMSLPImageHandler")
      return http_download_imslp(url, destination, timeout: timeout)
    end
    raise DownloadError, "Too many redirects" if redirect_limit.zero?

    uri = URI(url)

    # Use CloudflareBypass for protected hosts
    if needs_cloudflare_bypass?(uri.host)
      return http_download_via_bypass(url, destination, timeout: timeout)
    end

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 15
    http.read_timeout = timeout

    # Configure SSL to avoid CRL verification issues
    if http.use_ssl?
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.cert_store = OpenSSL::X509::Store.new
      http.cert_store.set_default_paths
    end

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "ScorebaseBot/1.0"

    response = http.request(request)

    case response
    when Net::HTTPSuccess
      File.binwrite(destination, response.body)
      response
    when Net::HTTPRedirection
      redirect_url = response["location"]
      redirect_url = URI.join(url, redirect_url).to_s unless redirect_url.start_with?("http")
      http_download(redirect_url, destination, redirect_limit: redirect_limit - 1, timeout: timeout)
    when Net::HTTPServerError
      # Retry on 5xx errors with exponential backoff
      if retries < MAX_RETRIES
        sleep(RETRY_DELAY * (2**retries))
        http_download(url, destination, redirect_limit: redirect_limit, timeout: timeout, retries: retries + 1)
      else
        raise DownloadError, "HTTP #{response.code} after #{MAX_RETRIES} retries: #{response.message}"
      end
    else
      raise DownloadError, "HTTP #{response.code}: #{response.message}"
    end
  rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET => e
    # Retry on network errors
    if retries < MAX_RETRIES
      sleep(RETRY_DELAY * (2**retries))
      http_download(url, destination, redirect_limit: redirect_limit, timeout: timeout, retries: retries + 1)
    else
      raise DownloadError, "#{e.class.name} after #{MAX_RETRIES} retries: #{e.message}"
    end
  end

  def needs_cloudflare_bypass?(host)
    CLOUDFLARE_PROTECTED_HOSTS.include?(host&.downcase)
  end

  def http_download_via_bypass(url, destination, timeout: 30, retries: 0)
    client = CloudflareBypassClient.new
    response = client.get(url, timeout: timeout)

    case response
    when Net::HTTPSuccess
      File.binwrite(destination, response.body)
      response
    when Net::HTTPServerError
      if retries < MAX_RETRIES
        sleep(RETRY_DELAY * (2**retries))
        http_download_via_bypass(url, destination, timeout: timeout, retries: retries + 1)
      else
        raise DownloadError, "HTTP #{response.code} via bypass after #{MAX_RETRIES} retries"
      end
    else
      raise DownloadError, "HTTP #{response.code} via CloudflareBypass: #{response.message}"
    end
  rescue Errno::ECONNREFUSED, Errno::EADDRNOTAVAIL => e
    raise DownloadError, "CloudflareBypass not available (#{e.class.name}): #{url}"
  rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET => e
    if retries < MAX_RETRIES
      sleep(RETRY_DELAY * (2**retries))
      http_download_via_bypass(url, destination, timeout: timeout, retries: retries + 1)
    else
      raise DownloadError, "#{e.class.name} via bypass after #{MAX_RETRIES} retries: #{e.message}"
    end
  end

  # IMSLP serves a download page with ads/countdown, but the real PDF URL is in data-id attribute
  # Flow: fetch HTML page -> extract data-id from #sm_dl_wait -> download from CDN URL
  def http_download_imslp(url, destination, timeout: 30)
    # Rate limit IMSLP requests to avoid IP bans (class-level so it persists across instances)
    @@last_imslp_request ||= Time.at(0) # rubocop:disable Style/ClassVars
    elapsed = Time.now - @@last_imslp_request
    sleep(IMSLP_RATE_LIMIT - elapsed) if elapsed < IMSLP_RATE_LIMIT
    @@last_imslp_request = Time.now

    uri = URI(url)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 15
    http.read_timeout = timeout
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.cert_store = OpenSSL::X509::Store.new
    http.cert_store.set_default_paths

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    request["Cookie"] = "imslpdisclaimeraccepted=yes; redirectPassed=1"

    response = http.request(request)

    # IMSLP sometimes 302-redirects to imslp.eu/linkhandler.php (intermediary page)
    if response.is_a?(Net::HTTPRedirection)
      cdn_url = response["location"]
      cdn_url = URI.join(url, cdn_url).to_s unless cdn_url.start_with?("http")
      cdn_url = URI::DEFAULT_PARSER.escape(cdn_url) unless cdn_url.ascii_only?

      # If redirected to imslp.eu linkhandler, fetch that page and extract the real PDF link
      if cdn_url.include?("imslp.eu/linkhandler.php")
        return http_download_imslp_eu(cdn_url, destination, timeout: timeout)
      end

      return http_download(cdn_url, destination, timeout: timeout)
    end

    unless response.is_a?(Net::HTTPSuccess)
      raise DownloadError, "IMSLP page fetch failed: HTTP #{response.code}"
    end

    # Extract direct CDN URL from data-id attribute
    # Pattern: <span id="sm_dl_wait" data-id="https://s9.imslp.org/files/...">
    match = response.body.match(/id="sm_dl_wait"[^>]*data-id="([^"]+)"/)
    unless match
      raise DownloadError, "Could not find IMSLP download URL in page"
    end

    cdn_url = CGI.unescapeHTML(match[1])
    cdn_url = URI::DEFAULT_PARSER.escape(cdn_url) unless cdn_url.ascii_only?
    http_download(cdn_url, destination, timeout: timeout)
  end

  # IMSLP-EU serves an intermediary HTML page with the real PDF link in an href
  # Flow: fetch HTML -> extract /files/...pdf href -> download from imslp.eu
  def http_download_imslp_eu(url, destination, timeout: 30)
    uri = URI(url)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 15
    http.read_timeout = timeout
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.cert_store = OpenSSL::X509::Store.new
    http.cert_store.set_default_paths

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    request["Cookie"] = "imslpdisclaimeraccepted=yes"

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      raise DownloadError, "IMSLP-EU page fetch failed: HTTP #{response.code}"
    end

    match = response.body.match(/href="(\/files\/[^"]+\.pdf)"/i)
    unless match
      raise DownloadError, "Could not find PDF link in IMSLP-EU page"
    end

    pdf_url = "https://imslp.eu#{match[1]}"
    pdf_url = URI::DEFAULT_PARSER.escape(pdf_url) unless pdf_url.ascii_only?
    http_download(pdf_url, destination, timeout: timeout)
  end

  class DownloadError < StandardError; end
end
