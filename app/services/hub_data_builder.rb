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

  # Historical periods mapped to genre tags in the database.
  # Note: lowercase "classical" in PDMX is a pop music tag, not the Classical period.
  # Uses GLOB for case-sensitive matching to distinguish them.
  PERIODS = {
    "Medieval" => ["Medieval", "Medieval music"],
    "Renaissance" => ["Renaissance", "Renaissance music"],
    "Baroque" => ["Baroque", "Baroque music"],
    "Classical" => ["Classical", "Classical music"],
    "Romantic" => ["Romantic", "Romantic music"],
    "Modern" => ["Modern", "Modern music", "Early 20th century", "Early 20th century music", "Contemporary"]
  }.freeze

  PERIOD_ORDER = %w[Medieval Renaissance Baroque Classical Romantic Modern].freeze

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

    # Slug lookups
    def find_by_slug(type, slug)
      data = public_send(type)
      data.find { |item| item[:slug] == slug }&.dig(:name)
    end

    private

    def fetch_or_build(key, &block)
      Rails.cache.fetch(key, expires_in: CACHE_FALLBACK_TTL, &block)
    end

    def build_composers
      valid_composers = ComposerMapping.normalizable.pluck(:normalized_name).uniq
      composer_counts = Score.where(composer: valid_composers).group(:composer).count

      build_hub_items(composer_counts)
    end

    def build_genres
      genre_counts = count_delimited_field(:genre, "-")
      build_hub_items(genre_counts)
    end

    def build_instruments
      instrument_counts = count_delimited_field(:instruments, /[;,]/) do |value|
        value.gsub(/\s*\(.*\)/, "").strip.downcase
      end

      build_hub_items(instrument_counts) do |name, count|
        { name: name.titleize, slug: name.parameterize, count: count }
      end
    end

    def build_periods
      PERIOD_ORDER.filter_map do |period_name|
        count = Score.by_period_strict(period_name).count
        next if count < THRESHOLD

        { name: period_name, slug: period_name.parameterize, count: count }
      end
    end

    # Generic builder for delimited string fields (genres, instruments)
    def count_delimited_field(field, delimiter)
      counts = Hash.new(0)

      Score.where.not(field => [nil, ""]).pluck(field).each do |str|
        str.split(delimiter).map(&:strip).reject(&:blank?).each do |value|
          normalized = block_given? ? yield(value) : value
          counts[normalized] += 1
        end
      end

      counts
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
