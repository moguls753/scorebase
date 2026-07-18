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

# Store sitemaps in storage/ (persisted across deploys via Kamal volume).
# Entrypoint symlinks public/sitemap.xml.gz -> storage/sitemaps/ so Thruster serves it.
SitemapGenerator::Sitemap.public_path = "storage/"
SitemapGenerator::Sitemap.sitemaps_path = "sitemaps"
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

  # Smart Search BETA tool (canonical product URL)
  add smart_search_path, changefreq: "weekly", priority: 0.9
  add smart_search_path(locale: :de), changefreq: "weekly", priority: 0.9

  # Pro/pricing landing page
  add pro_landing_path, changefreq: "monthly", priority: 0.7
  add pro_landing_path(locale: :de), changefreq: "monthly", priority: 0.7

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

  # Periods index
  add periods_path, changefreq: "weekly", priority: 0.9
  add periods_path(locale: :de), changefreq: "weekly", priority: 0.9

  # Artists index (SMD modern artists)
  add artists_path, changefreq: "weekly", priority: 0.9
  add artists_path(locale: :de), changefreq: "weekly", priority: 0.9

  # Ensembles index (SMD ensemble-category hubs)
  add ensembles_path, changefreq: "weekly", priority: 0.9
  add ensembles_path(locale: :de), changefreq: "weekly", priority: 0.9

  # ===========================================
  # INDIVIDUAL HUB PAGES (from HubDataBuilder)
  # ===========================================

  # Composer pages (uses ComposerMapping for clean data)
  composers = HubDataBuilder.composers
  composers.each do |item|
    add composer_path(slug: item[:slug]), changefreq: "weekly", priority: 0.8
    add composer_path(slug: item[:slug], locale: :de), changefreq: "weekly", priority: 0.8
  end

  # Artist pages (SMD modern artists - Taylor Swift, Hans Zimmer, etc.)
  artists = HubDataBuilder.artists
  artists.each do |item|
    add artist_path(slug: item[:slug]), changefreq: "weekly", priority: 0.8
    add artist_path(slug: item[:slug], locale: :de), changefreq: "weekly", priority: 0.8
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

  # Period pages (historical eras)
  periods = HubDataBuilder.periods
  periods.each do |item|
    add period_path(slug: item[:slug]), changefreq: "weekly", priority: 0.8
    add period_path(slug: item[:slug], locale: :de), changefreq: "weekly", priority: 0.8
  end

  # Ensemble pages (curated smd_category allowlist, dedup arrangements)
  # Keyword slug: (not positional) — the optional (:locale) route scope otherwise
  # binds a positional arg to :locale and raises.
  HubDataBuilder.ensembles.each do |item|
    add ensemble_path(slug: item[:slug]), changefreq: "weekly", priority: 0.8
    add ensemble_path(slug: item[:slug], locale: :de), changefreq: "weekly", priority: 0.8
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
      count = Score.active.where(composer: composer_item[:name])
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
      count = Score.active.by_genre(genre_item[:name])
                   .by_instrument(instrument_item[:name]).count
      next if count < threshold

      add genre_instrument_path(genre_slug: genre_item[:slug], instrument_slug: instrument_item[:slug]),
          changefreq: "weekly", priority: 0.7
      add genre_instrument_path(genre_slug: genre_item[:slug], instrument_slug: instrument_item[:slug], locale: :de),
          changefreq: "weekly", priority: 0.7
    end
  end

  # Period + Instrument combinations
  # e.g., "Classical Piano", "Baroque Violin"
  # Uses same scopes as controller for consistent counts
  periods.each do |period_item|
    instruments.each do |instrument_item|
      count = Score.active.by_period(period_item[:name])
                   .by_instrument(instrument_item[:name]).count
      next if count < threshold

      add period_instrument_path(period_slug: period_item[:slug], instrument_slug: instrument_item[:slug]),
          changefreq: "weekly", priority: 0.7
      add period_instrument_path(period_slug: period_item[:slug], instrument_slug: instrument_item[:slug], locale: :de),
          changefreq: "weekly", priority: 0.7
    end
  end

  # Instrument + Difficulty combinations (SEO landing pages)
  # e.g., "Beginner Piano", "Intermediate Violin"
  # High-value for long-tail SEO queries like "easy piano sheet music for beginners"
  difficulties = HubDataBuilder::DIFFICULTY_ORDER
  instruments.each do |instrument_item|
    difficulties.each do |difficulty_slug|
      count = Score.active.by_instrument(instrument_item[:name])
                   .by_difficulty(difficulty_slug).count
      next if count < threshold

      add instrument_difficulty_path(instrument_slug: instrument_item[:slug], difficulty_slug: difficulty_slug),
          changefreq: "weekly", priority: 0.8
      add instrument_difficulty_path(instrument_slug: instrument_item[:slug], difficulty_slug: difficulty_slug, locale: :de),
          changefreq: "weekly", priority: 0.8
    end
  end

  # ===========================================
  # SEASONAL PAGES (Christmas)
  # ===========================================
  # High-value for seasonal SEO queries like "christmas choir music free"

  # Christmas index page
  add christmas_path, changefreq: "yearly", priority: 0.8
  add christmas_path(locale: :de), changefreq: "yearly", priority: 0.8

  # Christmas choir (SATB)
  add christmas_choir_path, changefreq: "yearly", priority: 0.8
  add christmas_choir_path(locale: :de), changefreq: "yearly", priority: 0.8

  # Christmas + Instrument combinations (uses HubDataBuilder as single source of truth)
  HubDataBuilder::CHRISTMAS_INSTRUMENTS.each do |instrument_slug|
    count = Score.active.christmas.by_instrument(instrument_slug).count
    next if count < HubDataBuilder::CHRISTMAS_INSTRUMENT_THRESHOLD

    add christmas_instrument_path(instrument_slug: instrument_slug), changefreq: "yearly", priority: 0.7
    add christmas_instrument_path(instrument_slug: instrument_slug, locale: :de), changefreq: "yearly", priority: 0.7
  end

  # ===========================================
  # SMD GROUP REPRESENTATIVES (commercial buy pages)
  # ===========================================
  # Live DB query so the weekly SitemapRefreshJob auto-picks-up newly
  # imported/updated reps. Scope is representatives ONLY — hidden members
  # are canonicalized to their rep, and ungrouped standalone SMD products
  # are intentionally excluded (doorway-page risk).
  # Keyword id: (not positional) — the optional (:locale) route scope otherwise
  # binds a positional arg to :locale, raising "missing required keys: [:id]".
  Score.active.smd_group_representatives.find_each do |score|
    add score_path(id: score.id), lastmod: score.updated_at, changefreq: "monthly", priority: 0.6
    add score_path(id: score.id, locale: :de), lastmod: score.updated_at, changefreq: "monthly", priority: 0.6
  end
end
