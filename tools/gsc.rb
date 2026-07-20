#!/usr/bin/env ruby
# frozen_string_literal: true

# Google Search Console reader. Stdlib only — deliberately not a Rails
# integration: no gems, nothing in the bundle, and the service-account key stays
# outside the repo (GSC_KEY, default ~/.config/scorebase/gsc-key.json).
#
#   ruby tools/gsc.rb sites
#   ruby tools/gsc.rb sitemaps
#   ruby tools/gsc.rb query --dimensions page --days 90 --table
#   ruby tools/gsc.rb query --dimensions page,query --filter "page~~/scores/"
#   ruby tools/gsc.rb inspect https://scorebase.org/scores/313510
#
# query emits JSON on stdout so it pipes into jq or a rails runner join;
# --table prints a readable summary instead. Progress goes to stderr.

require "net/http"
require "json"
require "openssl"
require "base64"
require "uri"
require "date"
require "cgi"
require "optparse"

KEY_PATH = ENV.fetch("GSC_KEY", File.expand_path("~/.config/scorebase/gsc-key.json"))
SITE = ENV.fetch("GSC_SITE", "https://scorebase.org/")
SCOPE = "https://www.googleapis.com/auth/webmasters.readonly"
MAX_ROWS = 25_000

DIMENSIONS = %w[date query page country device searchAppearance].freeze
SEARCH_TYPES = %w[web image video news discover googleNews].freeze
OPERATORS = { "~~" => "contains", "==" => "equals", "!~" => "notContains", "!=" => "notEquals",
              "=@" => "includingRegex", "!@" => "excludingRegex" }.freeze

def b64(data) = Base64.urlsafe_encode64(data, padding: false)

def access_token
  unless File.exist?(KEY_PATH)
    abort("Kein Key unter #{KEY_PATH}. Pfad via GSC_KEY setzen.")
  end

  key = JSON.parse(File.read(KEY_PATH))
  now = Time.now.to_i
  header = b64({ alg: "RS256", typ: "JWT" }.to_json)
  claims = b64({ iss: key["client_email"], scope: SCOPE, aud: key["token_uri"],
                 exp: now + 3600, iat: now }.to_json)
  signature = OpenSSL::PKey::RSA.new(key["private_key"])
                                .sign(OpenSSL::Digest::SHA256.new, "#{header}.#{claims}")

  res = Net::HTTP.post_form(URI(key["token_uri"]),
                            "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
                            "assertion" => "#{header}.#{claims}.#{b64(signature)}")
  body = JSON.parse(res.body)
  abort("Token-Fehler: #{body}") unless body["access_token"]
  body["access_token"]
end

def api(url, token, payload = nil)
  uri = URI(url)
  req = payload ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
  req["Authorization"] = "Bearer #{token}"
  req["Content-Type"] = "application/json"
  req.body = payload.to_json if payload

  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
  body = res.body.to_s.empty? ? {} : JSON.parse(res.body)
  abort("API-Fehler #{res.code}: #{body['error'] || res.body}") unless res.is_a?(Net::HTTPSuccess)
  body
end

def webmasters(path, token, payload = nil)
  api("https://www.googleapis.com/webmasters/v3/#{path}", token, payload)
end

# "page~~/scores/" -> { dimension: "page", operator: "contains", expression: "/scores/" }
def parse_filter(str)
  op_key = OPERATORS.keys.find { |o| str.include?(o) } or
    abort("Filter ohne Operator. Erlaubt: #{OPERATORS.keys.join(' ')}")
  dimension, expression = str.split(op_key, 2)
  { dimension: dimension, operator: OPERATORS[op_key], expression: expression }
end

def fetch_all(token, opts)
  rows = []
  start_row = 0
  loop do
    payload = {
      startDate: opts[:start], endDate: opts[:end],
      dimensions: opts[:dimensions], type: opts[:type],
      rowLimit: MAX_ROWS, startRow: start_row,
      dataState: opts[:final] ? "final" : "all"
    }
    payload[:dimensionFilterGroups] = [ { filters: opts[:filters] } ] if opts[:filters].any?

    body = webmasters("sites/#{CGI.escape(opts[:site])}/searchAnalytics/query", token, payload)
    batch = body["rows"] || []
    rows.concat(batch)
    warn "  geholt: #{rows.size}"
    break if batch.size < MAX_ROWS || (opts[:limit] && rows.size >= opts[:limit])

    start_row += MAX_ROWS
  end
  opts[:limit] ? rows.first(opts[:limit]) : rows
end

def print_table(rows, dimensions)
  if rows.empty?
    puts "Keine Zeilen."
    return
  end

  imp = rows.sum { |r| r["impressions"] }
  clk = rows.sum { |r| r["clicks"] }
  pos = rows.sum { |r| r["position"] * r["impressions"] } / imp.to_f
  puts "Zeilen: #{rows.size}   Impressions: #{imp}   Klicks: #{clk}   " \
       "CTR: #{(clk * 100.0 / imp).round(2)}%   Ø Position: #{pos.round(1)}"
  puts
  puts "#{'Impr'.rjust(8)} #{'Klicks'.rjust(7)} #{'CTR'.rjust(7)} #{'Pos'.rjust(6)}  #{dimensions.join(' / ')}"
  rows.sort_by { |r| -r["impressions"] }.first(40).each do |r|
    ctr = r["impressions"].zero? ? 0 : r["clicks"] * 100.0 / r["impressions"]
    key = r["keys"].join(" / ").sub("https://scorebase.org", "")
    puts "#{r['impressions'].to_s.rjust(8)} #{r['clicks'].to_s.rjust(7)} " \
         "#{format('%.2f%%', ctr).rjust(7)} #{r['position'].round(1).to_s.rjust(6)}  #{key[0, 70]}"
  end
  puts "... (#{rows.size - 40} weitere)" if rows.size > 40
end

command = ARGV.shift
token = access_token

case command
when "sites"
  entries = webmasters("sites", token)["siteEntry"] || []
  if entries.empty?
    warn "Keine Properties. Service Account in Search Console unter"
    warn "Einstellungen -> Nutzer und Berechtigungen hinzufuegen."
  end
  entries.each { |e| puts "#{e['permissionLevel'].ljust(22)} #{e['siteUrl']}" }

when "sitemaps"
  site = ARGV[0] || SITE
  maps = webmasters("sites/#{CGI.escape(site)}/sitemaps", token)["sitemap"] || []
  puts "Keine Sitemap registriert." if maps.empty?
  maps.each do |s|
    puts s["path"]
    puts "  eingereicht:  #{s['lastSubmitted']}"
    puts "  abgerufen:    #{s['lastDownloaded'] || '(nie)'}"
    puts "  pending: #{s['isPending']}   Fehler: #{s['errors'] || 0}   Warnungen: #{s['warnings'] || 0}"
    (s["contents"] || []).each { |c| puts "  #{c['type']}: eingereicht=#{c['submitted']} indexiert=#{c['indexed']}" }
  end

when "inspect"
  url = ARGV[0] or abort("Aufruf: gsc.rb inspect <url>")
  res = api("https://searchconsole.googleapis.com/v1/urlInspection/index:inspect", token,
            { inspectionUrl: url, siteUrl: SITE, languageCode: "de" })
  r = res.dig("inspectionResult") || {}
  idx = r["indexStatusResult"] || {}
  puts "URL: #{url}"
  puts "  Verdict:        #{idx['verdict']}"
  puts "  Coverage:       #{idx['coverageState']}"
  puts "  Roboter:        #{idx['robotsTxtState']}   Indexierung: #{idx['indexingState']}"
  puts "  Letzter Crawl:  #{idx['lastCrawlTime'] || '(nie gecrawlt)'}"
  puts "  Canonical (G):  #{idx['googleCanonical']}"
  puts "  Canonical (du): #{idx['userCanonical']}"
  puts "  Sitemaps:       #{(idx['sitemap'] || []).join(', ')}"
  puts "  Mobile:         #{r.dig('mobileUsabilityResult', 'verdict')}"
  puts "  Rich Results:   #{r.dig('richResultsResult', 'verdict') || '(keine)'}"

when "query"
  opts = { site: SITE, dimensions: [ "page" ], type: "web", filters: [],
           limit: nil, table: false, final: false }
  days = 90

  OptionParser.new do |o|
    o.banner = "Aufruf: gsc.rb query [optionen]"
    o.on("--dimensions LIST", "#{DIMENSIONS.join(', ')} (kommagetrennt)") { |v| opts[:dimensions] = v.split(",") }
    o.on("--days N", Integer, "Zeitraum in Tagen (Standard 90)") { |v| days = v }
    o.on("--start DATE", "Startdatum YYYY-MM-DD") { |v| opts[:start] = v }
    o.on("--end DATE", "Enddatum YYYY-MM-DD") { |v| opts[:end] = v }
    o.on("--type TYPE", "#{SEARCH_TYPES.join(', ')} (Standard web)") { |v| opts[:type] = v }
    o.on("--filter EXPR", "z.B. page~~/scores/ , query==noten , page!~/de/") { |v| opts[:filters] << parse_filter(v) }
    o.on("--limit N", Integer, "max. Zeilen") { |v| opts[:limit] = v }
    o.on("--site URL", "Property (Standard #{SITE})") { |v| opts[:site] = v }
    o.on("--final", "nur finalisierte Daten (ohne die letzten ~3 Tage)") { opts[:final] = true }
    o.on("--table", "lesbare Tabelle statt JSON") { opts[:table] = true }
  end.parse!(ARGV)

  opts[:end] ||= Date.today.to_s
  opts[:start] ||= (Date.parse(opts[:end]) - days).to_s
  bad = opts[:dimensions] - DIMENSIONS
  abort("Unbekannte Dimension: #{bad.join(', ')}") if bad.any?

  warn "#{opts[:start]} bis #{opts[:end]}, Dimensionen: #{opts[:dimensions].join(',')}, Typ: #{opts[:type]}"
  rows = fetch_all(token, opts)
  opts[:table] ? print_table(rows, opts[:dimensions]) : puts(JSON.generate(rows))

else
  puts <<~USAGE
    Aufruf: ruby tools/gsc.rb <befehl>

      sites                Properties auflisten, auf die der Service Account Zugriff hat
      sitemaps [site]      Sitemap-Status: abgerufen, Fehler, eingereicht/indexiert
      inspect <url>        Indexstatus einer URL (Limit 2000/Tag)
      query [optionen]     Search Analytics; --help fuer Optionen

    Key: #{KEY_PATH} (via GSC_KEY)
  USAGE
end
