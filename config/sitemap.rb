# Sitemap configuration for ScoreBase
#
# Generate: rails sitemap:refresh
# Generate without ping: rails sitemap:refresh:no_ping
#
# For production, run as cron job (e.g., weekly):
# 0 2 * * 0 cd /path/to/app && bin/rails sitemap:refresh RAILS_ENV=production

SitemapGenerator::Sitemap.default_host = ENV.fetch("SITE_URL", "https://scorebase.org")

# Store sitemaps in public/ directory (compressed)
SitemapGenerator::Sitemap.public_path = "public/"
SitemapGenerator::Sitemap.sitemaps_path = ""
SitemapGenerator::Sitemap.compress = true

# Thresholds for hub pages (must match controller)
THRESHOLDS = {
  composer: 12,
  genre: 20,
  instrument: 15,
  voicing: 20
}.freeze

SitemapGenerator::Sitemap.create do
  # ===========================================
  # STATIC PAGES (highest priority)
  # ===========================================

  # Root/Home (both locales)
  add root_path, changefreq: "daily", priority: 1.0
  add root_path(locale: :de), changefreq: "daily", priority: 1.0

  # About page
  add about_path, changefreq: "monthly", priority: 0.6
  add about_path(locale: :de), changefreq: "monthly", priority: 0.6

  # Impressum (legal, low priority)
  add impressum_path, changefreq: "yearly", priority: 0.2
  add impressum_path(locale: :de), changefreq: "yearly", priority: 0.2

  # ===========================================
  # HUB INDEX PAGES (high priority - important for SEO)
  # ===========================================

  # Composers index
  add composers_path, changefreq: "weekly", priority: 0.9
  add composers_path(locale: :de), changefreq: "weekly", priority: 0.9

  # Genres index
  add genres_path, changefreq: "weekly", priority: 0.9
  add genres_path(locale: :de), changefreq: "weekly", priority: 0.9

  # Instruments index
  add instruments_path, changefreq: "weekly", priority: 0.9
  add instruments_path(locale: :de), changefreq: "weekly", priority: 0.9

  # Voicing index
  add voicing_index_path, changefreq: "weekly", priority: 0.9
  add voicing_index_path(locale: :de), changefreq: "weekly", priority: 0.9

  # ===========================================
  # INDIVIDUAL HUB PAGES (high priority)
  # ===========================================

  # Composer pages
  composer_counts = Score.where.not(composer: [nil, ""])
                         .group(:composer)
                         .count
                         .select { |_, count| count >= THRESHOLDS[:composer] }

  composer_counts.each do |name, _count|
    slug = name.parameterize
    add composer_path(slug: slug), changefreq: "weekly", priority: 0.8
    add composer_path(slug: slug, locale: :de), changefreq: "weekly", priority: 0.8
  end

  # Genre pages
  genre_counts = Hash.new(0)
  Score.where.not(genres: [nil, ""]).pluck(:genres).each do |genres_str|
    genres_str.split("-").map(&:strip).reject(&:blank?).each do |genre|
      genre_counts[genre] += 1
    end
  end

  genre_counts.select { |_, count| count >= THRESHOLDS[:genre] }.each do |name, _count|
    slug = name.parameterize
    add genre_path(slug: slug), changefreq: "weekly", priority: 0.8
    add genre_path(slug: slug, locale: :de), changefreq: "weekly", priority: 0.8
  end

  # Instrument pages
  instrument_counts = Hash.new(0)
  Score.where.not(instruments: [nil, ""]).pluck(:instruments).each do |instruments_str|
    instruments_str.split(/[;,]/).map(&:strip).reject(&:blank?).each do |instrument|
      normalized = instrument.gsub(/\s*\(.*\)/, "").strip.downcase
      instrument_counts[normalized] += 1
    end
  end

  instrument_counts.select { |_, count| count >= THRESHOLDS[:instrument] }.each do |name, _count|
    slug = name.parameterize
    add instrument_path(slug: slug), changefreq: "weekly", priority: 0.8
    add instrument_path(slug: slug, locale: :de), changefreq: "weekly", priority: 0.8
  end

  # Voicing pages
  voicing_counts = Score.where.not(voicing: [nil, ""])
                        .group(:voicing)
                        .count
                        .select { |_, count| count >= THRESHOLDS[:voicing] }

  voicing_counts.each do |name, _count|
    slug = name.parameterize
    add voicing_path(slug: slug), changefreq: "weekly", priority: 0.8
    add voicing_path(slug: slug, locale: :de), changefreq: "weekly", priority: 0.8
  end

  # ===========================================
  # TOP POPULAR SCORES (medium priority)
  # Only include top 10,000 by popularity to keep sitemap manageable
  # ===========================================

  Score.order_by_popularity.limit(10_000).find_each do |score|
    add score_path(score), lastmod: score.updated_at, changefreq: "monthly", priority: 0.5
    add score_path(score, locale: :de), lastmod: score.updated_at, changefreq: "monthly", priority: 0.5
  end
end
