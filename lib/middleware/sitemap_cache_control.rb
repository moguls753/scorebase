# Serves sitemap files with a short TTL instead of the global 1-year
# public_file_server header, so weekly regenerations propagate through
# Cloudflare instead of being pinned at the edge for a year. Wraps
# ActionDispatch::Static (inserted before it) to override the header it sets.
#
# Lives in a Zeitwerk-ignored dir (config.autoload_lib ignore) and is
# require'd from production.rb, because the middleware stack is assembled at
# environment-config time, before autoloading is active.
class SitemapCacheControl
  SITEMAP_PATH = %r{\A/sitemap[\w.-]*\.xml(?:\.gz)?\z}i

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    if env["PATH_INFO"].to_s.match?(SITEMAP_PATH)
      headers.delete("Cache-Control")
      headers.delete("cache-control")
      headers["cache-control"] = "public, max-age=3600"
    end
    [ status, headers, body ]
  end
end
