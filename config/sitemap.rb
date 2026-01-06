# Sitemap configuration for ScoreBase
#
# Generate: rails sitemap:refresh
# Generate without ping: rails sitemap:refresh:no_ping
#
# For production, run as cron job (e.g., weekly):
# 0 2 * * 0 cd /path/to/app && bin/rails sitemap:refresh RAILS_ENV=production
#
# Uses HubDataBuilder as single source of truth for hub page data.
# Genres/instruments only include normalized scores (excludes junk data).

SitemapGenerator::Sitemap.default_host = ENV.fetch("SITE_URL", "https://scorebase.org")

# Store sitemaps in public/ directory (compressed)
SitemapGenerator::Sitemap.public_path = "public/"
SitemapGenerator::Sitemap.sitemaps_path = ""
SitemapGenerator::Sitemap.compress = true

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

  # Pro landing page (Smart Search)
  add pro_landing_path, changefreq: "weekly", priority: 0.8
  add pro_landing_path(locale: :de), changefreq: "weekly", priority: 0.8

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

  # ===========================================
  # INDIVIDUAL HUB PAGES (from HubDataBuilder)
  # ===========================================

  # Composer pages (uses ComposerMapping for clean data)
  composers = HubDataBuilder.composers
  composers.each do |item|
    add composer_path(slug: item[:slug]), changefreq: "weekly", priority: 0.8
    add composer_path(slug: item[:slug], locale: :de), changefreq: "weekly", priority: 0.8
  end

  # Genre pages (only normalized scores, via by_genre scope)
  genres = HubDataBuilder.genres
  genres.each do |item|
    add genre_path(slug: item[:slug]), changefreq: "weekly", priority: 0.8
    add genre_path(slug: item[:slug], locale: :de), changefreq: "weekly", priority: 0.8
  end

  # Instrument pages (allowlist ensures clean names, LIKE matches all scores)
  instruments = HubDataBuilder.instruments
  instruments.each do |item|
    add instrument_path(slug: item[:slug]), changefreq: "weekly", priority: 0.8
    add instrument_path(slug: item[:slug], locale: :de), changefreq: "weekly", priority: 0.8
  end

  # ===========================================
  # COMBINED HUB PAGES (Tier 1 - important for SEO)
  # ===========================================
  # Only include combinations where both sides are from HubDataBuilder
  # (i.e., normalized/curated data only)

  threshold = HubDataBuilder::THRESHOLD

  # Composer + Instrument combinations
  # e.g., "Bach Piano", "Mozart Violin"
  # Uses same scopes as controller for consistent counts
  composers.each do |composer_item|
    instruments.each do |instrument_item|
      count = Score.where(composer: composer_item[:name])
                   .by_instrument(instrument_item[:name]).count
      next if count < threshold

      add composer_instrument_path(composer_slug: composer_item[:slug], instrument_slug: instrument_item[:slug]),
          changefreq: "weekly", priority: 0.7
      add composer_instrument_path(composer_slug: composer_item[:slug], instrument_slug: instrument_item[:slug], locale: :de),
          changefreq: "weekly", priority: 0.7
    end
  end

  # Genre + Instrument combinations
  # e.g., "Sacred Choir", "Jazz Saxophone"
  # Uses same scopes as controller for consistent counts
  genres.each do |genre_item|
    instruments.each do |instrument_item|
      count = Score.by_genre(genre_item[:name])
                   .by_instrument(instrument_item[:name]).count
      next if count < threshold

      add genre_instrument_path(genre_slug: genre_item[:slug], instrument_slug: instrument_item[:slug]),
          changefreq: "weekly", priority: 0.7
      add genre_instrument_path(genre_slug: genre_item[:slug], instrument_slug: instrument_item[:slug], locale: :de),
          changefreq: "weekly", priority: 0.7
    end
  end

  # ===========================================
  # INDIVIDUAL SCORES
  # ===========================================
  # NOT included in sitemap by design.
  # Individual scores are discovered by Google through:
  # 1. Internal links from hub pages (/composers/bach, /genres/classical)
  # 2. Natural crawling from the score index
  #
  # This keeps the sitemap focused on high-value landing pages
  # that target actual search queries like "Bach sheet music".
end
