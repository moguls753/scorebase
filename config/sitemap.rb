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

# Unified threshold for all hub pages (must match controller)
THRESHOLD = 10

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

  # ===========================================
  # INDIVIDUAL HUB PAGES (high priority)
  # ===========================================

  # Composer pages - group by slug to avoid duplicates and aggregate counts
  composer_counts = Score.where.not(composer: [nil, ""])
                         .group(:composer)
                         .count

  # Group composers by slug (e.g., "Bach", "BACH" → both slug to "bach")
  by_slug = Hash.new { |h, k| h[k] = { names: [], total: 0 } }
  composer_counts.each do |name, count|
    slug = name.parameterize
    by_slug[slug][:names] << name
    by_slug[slug][:total] += count
  end

  # Only include slugs with enough total scores
  by_slug.select { |_, data| data[:total] >= THRESHOLD }.each do |slug, _|
    add composer_path(slug: slug), changefreq: "weekly", priority: 0.8
    add composer_path(slug: slug, locale: :de), changefreq: "weekly", priority: 0.8
  end

  # Genre pages
  genre_counts = Hash.new(0)
  Score.where.not(genre: [nil, ""]).pluck(:genre).each do |genres_str|
    genres_str.split("-").map(&:strip).reject(&:blank?).each do |genre|
      genre_counts[genre] += 1
    end
  end

  genre_counts.select { |_, count| count >= THRESHOLD }.each do |name, _count|
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

  instrument_counts.select { |_, count| count >= THRESHOLD }.each do |name, _count|
    slug = name.parameterize
    add instrument_path(slug: slug), changefreq: "weekly", priority: 0.8
    add instrument_path(slug: slug, locale: :de), changefreq: "weekly", priority: 0.8
  end

  # ===========================================
  # COMBINED HUB PAGES (Tier 1 - important for SEO)
  # ===========================================

  # Composer + Instrument combinations
  # e.g., "Bach Piano", "Mozart Violin"
  by_slug.select { |_, data| data[:total] >= THRESHOLD }.each do |composer_slug, data|
    # Use exact match on all composer name variants (matches controller logic)
    composer_names = data[:names]

    # Find instruments that have enough scores with this composer
    instrument_for_composer = Hash.new(0)
    Score.where(composer: composer_names)  # Exact match, not LIKE
         .where.not(instruments: [nil, ""])
         .pluck(:instruments).each do |instruments_str|
      instruments_str.split(/[;,]/).map(&:strip).reject(&:blank?).each do |instrument|
        normalized = instrument.gsub(/\s*\(.*\)/, "").strip.downcase
        instrument_for_composer[normalized] += 1
      end
    end

    # Add combined pages with threshold
    instrument_for_composer.select { |_, count| count >= THRESHOLD }.each do |instrument_name, _|
      instrument_slug = instrument_name.parameterize
      add composer_instrument_path(composer_slug: composer_slug, instrument_slug: instrument_slug),
          changefreq: "weekly", priority: 0.7
      add composer_instrument_path(composer_slug: composer_slug, instrument_slug: instrument_slug, locale: :de),
          changefreq: "weekly", priority: 0.7
    end
  end

  # Genre + Instrument combinations
  # e.g., "Classical Piano", "Jazz Saxophone"
  genre_counts.select { |_, count| count >= THRESHOLD }.each do |genre_name, _|
    genre_slug = genre_name.parameterize

    # Find instruments that have enough scores with this genre
    instrument_for_genre = Hash.new(0)
    Score.where("genre LIKE ?", "%#{Score.sanitize_sql_like(genre_name)}%")
         .where.not(instruments: [nil, ""])
         .pluck(:instruments).each do |instruments_str|
      instruments_str.split(/[;,]/).map(&:strip).reject(&:blank?).each do |instrument|
        normalized = instrument.gsub(/\s*\(.*\)/, "").strip.downcase
        instrument_for_genre[normalized] += 1
      end
    end

    # Add combined pages with threshold
    instrument_for_genre.select { |_, count| count >= THRESHOLD }.each do |instrument_name, _|
      instrument_slug = instrument_name.parameterize
      add genre_instrument_path(genre_slug: genre_slug, instrument_slug: instrument_slug),
          changefreq: "weekly", priority: 0.7
      add genre_instrument_path(genre_slug: genre_slug, instrument_slug: instrument_slug, locale: :de),
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
