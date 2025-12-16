# frozen_string_literal: true

class HubCacheWarmJob < ApplicationJob
  queue_as :default

  CACHE_TTL = 1.week
  THRESHOLD = 10

  def perform
    Rails.logger.info "[HubCacheWarmJob] Starting cache warm..."

    warm_genres
    warm_instruments
    warm_composers
    warm_voicings

    Rails.logger.info "[HubCacheWarmJob] Cache warm complete"
  end

  private

  def warm_genres
    genre_counts = Hash.new(0)
    Score.where.not(genres: [nil, ""]).pluck(:genres).each do |str|
      str.split("-").map(&:strip).reject(&:blank?).each { |g| genre_counts[g] += 1 }
    end

    genres = genre_counts
      .select { |_, count| count >= THRESHOLD }
      .sort_by { |_, count| -count }
      .map { |name, count| { name: name, slug: name.parameterize, count: count } }

    Rails.cache.write("hub/genres", genres, expires_in: CACHE_TTL)
    Rails.logger.info "[HubCacheWarmJob] Cached #{genres.size} genres"
  end

  def warm_instruments
    instrument_counts = Hash.new(0)
    Score.where.not(instruments: [nil, ""]).pluck(:instruments).each do |str|
      str.split(/[;,]/).map(&:strip).reject(&:blank?).each do |inst|
        normalized = inst.gsub(/\s*\(.*\)/, "").strip.downcase
        instrument_counts[normalized] += 1
      end
    end

    instruments = instrument_counts
      .select { |_, count| count >= THRESHOLD }
      .sort_by { |_, count| -count }
      .map { |name, count| { name: name.titleize, slug: name.parameterize, count: count } }

    Rails.cache.write("hub/instruments", instruments, expires_in: CACHE_TTL)
    Rails.logger.info "[HubCacheWarmJob] Cached #{instruments.size} instruments"
  end

  def warm_composers
    valid_composers = ComposerMapping.normalizable.pluck(:normalized_name).uniq
    composer_counts = Score.where(composer: valid_composers).group(:composer).count

    composers = composer_counts
      .select { |_, count| count >= THRESHOLD }
      .sort_by { |_, count| -count }
      .map { |name, count| { name: name, slug: name.parameterize, count: count } }

    Rails.cache.write("hub/composers", composers, expires_in: CACHE_TTL)
    Rails.logger.info "[HubCacheWarmJob] Cached #{composers.size} composers"
  end

  def warm_voicings
    voicing_counts = Score.where.not(voicing: [nil, ""]).group(:voicing).count

    voicings = voicing_counts
      .select { |_, count| count >= THRESHOLD }
      .sort_by { |_, count| -count }
      .map { |name, count| { name: name, slug: name.parameterize, count: count } }

    Rails.cache.write("hub/voicings", voicings, expires_in: CACHE_TTL)
    Rails.logger.info "[HubCacheWarmJob] Cached #{voicings.size} voicings"
  end
end
