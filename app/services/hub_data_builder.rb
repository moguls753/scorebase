# frozen_string_literal: true

# Builds and caches hub page data for browse pages.
# Single source of truth for hub data generation logic.
#
# Usage:
#   HubDataBuilder.composers  # Returns cached data, builds if missing
#   HubDataBuilder.warm_all   # Pre-warms all caches (called by HubCacheWarmJob)
#
class HubDataBuilder
  CACHE_TTL = 1.week
  CACHE_FALLBACK_TTL = 1.day
  THRESHOLD = 10

  # Historical periods mapped to values the LLM normalizer might output.
  # by_period scope queries the normalized `period` column directly.
  PERIODS = {
    "Medieval" => ["Medieval", "Medieval music"],
    "Renaissance" => ["Renaissance", "Renaissance music", "Late Renaissance"],
    "Baroque" => ["Baroque", "Baroque music"],
    "Classical" => ["Classical", "Classical music"],
    "Romantic" => ["Romantic", "Romantic music", "Late Romantic", "Early Romantic", "19th Century"],
    "Impressionist" => ["Impressionist", "Impressionism", "Impressionistic"],
    "Modern" => [
      "Modern", "Modern music", "Contemporary",
      "20th Century", "21st Century",
      "Early 20th Century", "Early 20th century", "Early 20th century music"
    ]
  }.freeze

  PERIOD_ORDER = %w[Medieval Renaissance Baroque Classical Romantic Impressionist Modern].freeze

  # ===========================================
  # VALID INSTRUMENTS (allowlist for hub pages)
  # ===========================================
  # Uses LIKE matching, so "guitar" matches "electric guitar", "bass guitar", etc.
  # Keep entries minimal - only add specific variants if they need a separate hub page.
  VALID_INSTRUMENTS = [
    # Keyboard
    "piano", "organ", "harpsichord", "clavichord", "celesta", "harmonium",
    "accordion", "keyboard", "synthesizer",

    # Strings - Bowed
    "violin", "viola", "cello", "double bass", "fiddle",

    # Strings - Plucked
    "guitar", "harp", "lute", "theorbo", "mandolin", "banjo", "ukulele",

    # Woodwinds
    "flute", "piccolo", "recorder",
    "oboe", "english horn",
    "clarinet", "basset horn",
    "bassoon", "contrabassoon",
    "saxophone",

    # Brass
    "trumpet", "cornet", "flugelhorn",
    "horn",
    "trombone",
    "tuba", "euphonium",

    # Percussion
    "timpani", "xylophone", "marimba", "vibraphone", "glockenspiel",
    "percussion", "drums",

    # Voice
    "voice"
  ].freeze

  # ===========================================
  # VALID GENRES (loaded from config/genre_vocabulary.yml)
  # ===========================================
  # Single source of truth for both LLM classification and hub pages.
  GENRE_VOCABULARY_PATH = Rails.root.join("config/genre_vocabulary.yml").freeze
  VALID_GENRES = YAML.load_file(GENRE_VOCABULARY_PATH).fetch("genres").freeze

  class << self
    # Public accessors - read from cache with fallback to building
    def composers
      fetch_or_build("hub/composers") { build_composers }
    end

    def genres
      fetch_or_build("hub/genres") { build_genres }
    end

    def instruments
      fetch_or_build("hub/instruments") { build_instruments }
    end

    def periods
      fetch_or_build("hub/periods") { build_periods }
    end

    # Pre-warm all caches (called by HubCacheWarmJob)
    def warm_all
      Rails.logger.info "[HubDataBuilder] Starting cache warm..."

      {
        composers: build_composers,
        genres: build_genres,
        instruments: build_instruments,
        periods: build_periods
      }.each do |key, data|
        Rails.cache.write("hub/#{key}", data, expires_in: CACHE_TTL)
        Rails.logger.info "[HubDataBuilder] Cached #{data.size} #{key}"
      end

      Rails.logger.info "[HubDataBuilder] Cache warm complete"
    end

    # Slug lookups - verifies item still meets threshold (cache can be stale)
    def find_by_slug(type, slug)
      data = public_send(type)
      item = data.find { |i| i[:slug] == slug }
      return nil unless item

      name = item[:name]
      count = current_count(type, name)
      count >= THRESHOLD ? name : nil
    end

    private

    def current_count(type, name)
      case type
      when :composers then Score.where(composer: name).count
      when :genres then Score.by_genre(name).count
      when :instruments then Score.by_instrument(name).count
      when :periods then Score.by_period(name).count
      else 0
      end
    end

    def fetch_or_build(key, &block)
      Rails.cache.fetch(key, expires_in: CACHE_FALLBACK_TTL, &block)
    end

    def build_composers
      valid_composers = ComposerMapping.normalizable.pluck(:normalized_name).uniq
      composer_counts = Score.where(composer: valid_composers).group(:composer).count

      build_hub_items(composer_counts)
    end

    def build_genres
      # Count using by_genre scope (exact match + normalized) so counts match actual results
      VALID_GENRES.filter_map do |genre|
        count = Score.by_genre(genre).count
        next if count < THRESHOLD

        { name: genre, slug: genre.parameterize, count: count }
      end.sort_by { |item| -item[:count] }
    end

    def build_instruments
      # Count using LIKE matching (same as by_instrument scope) so counts match actual results
      VALID_INSTRUMENTS.filter_map do |instrument|
        count = Score.by_instrument(instrument).count
        next if count < THRESHOLD

        { name: instrument.titleize, slug: instrument.parameterize, count: count }
      end.sort_by { |item| -item[:count] }
    end

    def build_periods
      PERIOD_ORDER.filter_map do |period_name|
        count = Score.by_period(period_name).count
        next if count < THRESHOLD

        { name: period_name, slug: period_name.parameterize, count: count }
      end
    end

    # Convert counts hash to sorted hub items array
    def build_hub_items(counts)
      counts
        .select { |_, count| count >= THRESHOLD }
        .sort_by { |_, count| -count }
        .map do |name, count|
          if block_given?
            yield(name, count)
          else
            { name: name, slug: name.parameterize, count: count }
          end
        end
    end
  end
end
