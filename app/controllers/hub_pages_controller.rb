class HubPagesController < ApplicationController
  THRESHOLD = 10

  before_action :set_page_params

  def composers_index
    @composers = composers_with_counts
    @page_title = t("hub.composers_title")
    @page_description = t("hub.composers_description", count: @composers.size)
  end

  def genres_index
    @genres = genres_with_counts
    @page_title = t("hub.genres_title")
    @page_description = t("hub.genres_description", count: @genres.size)
  end

  def instruments_index
    @instruments = instruments_with_counts
    @page_title = t("hub.instruments_title")
    @page_description = t("hub.instruments_description", count: @instruments.size)
  end

  def voicing_index
    @voicings = voicings_with_counts
    @page_title = t("hub.voicing_title")
    @page_description = t("hub.voicing_description", count: @voicings.size)
  end

  def composer
    @composer_names = find_composers_by_slug(params[:slug])
    not_found if @composer_names.empty?

    @composer_name = @composer_names.first

    @scores = Score.where(composer: @composer_names)
    @scores = apply_sorting(@scores).page(params[:page])
    @total_count = @scores.total_count

    @page_title = t("hub.composer_page_title", name: @composer_name)
    @page_description = t("hub.composer_page_description", name: @composer_name, count: @total_count)
  end

  def genre
    @genre_name = find_genre_by_slug(params[:slug])
    not_found unless @genre_name

    @scores = Score.by_genre(@genre_name)
    @scores = apply_sorting(@scores).page(params[:page])
    @total_count = @scores.total_count

    @page_title = t("hub.genre_page_title", name: @genre_name)
    @page_description = t("hub.genre_page_description", name: @genre_name, count: @total_count)
  end

  def instrument
    @instrument_name = find_instrument_by_slug(params[:slug])
    not_found unless @instrument_name

    @scores = scores_by_instrument(@instrument_name)
    @scores = apply_sorting(@scores).page(params[:page])
    @total_count = @scores.total_count

    @page_title = t("hub.instrument_page_title", name: @instrument_name)
    @page_description = t("hub.instrument_page_description", name: @instrument_name, count: @total_count)
  end

  def voicing
    @voicing_name = find_voicing_by_slug(params[:slug])
    not_found unless @voicing_name

    @scores = scores_by_voicing(@voicing_name)
    @scores = apply_sorting(@scores).page(params[:page])
    @total_count = @scores.total_count

    @page_title = t("hub.voicing_page_title", name: @voicing_name)
    @page_description = t("hub.voicing_page_description", name: @voicing_name, count: @total_count)
  end

  def composer_instrument
    @composer_names = find_composers_by_slug(params[:composer_slug])
    @instrument_name = find_instrument_by_slug(params[:instrument_slug])
    not_found if @composer_names.empty? || @instrument_name.nil?

    @composer_name = @composer_names.first

    @scores = Score.where(composer: @composer_names)
    @scores = scores_by_instrument_query(@scores, @instrument_name)
    @scores = apply_sorting(@scores)
    @total_count = @scores.count
    @scores = @scores.page(params[:page])

    not_found if @total_count < THRESHOLD

    @page_title = t("hub.composer_instrument_title", composer: @composer_name, instrument: @instrument_name)
    @page_description = t("hub.composer_instrument_description",
      composer: @composer_name, instrument: @instrument_name, count: @total_count)
  end

  def genre_instrument
    @genre_name = find_genre_by_slug(params[:genre_slug])
    @instrument_name = find_instrument_by_slug(params[:instrument_slug])
    not_found unless @genre_name && @instrument_name

    @scores = Score.by_genre(@genre_name)
    @scores = scores_by_instrument_query(@scores, @instrument_name)
    @scores = apply_sorting(@scores)
    @total_count = @scores.count
    @scores = @scores.page(params[:page])

    not_found if @total_count < THRESHOLD

    @page_title = t("hub.genre_instrument_title", genre: @genre_name, instrument: @instrument_name)
    @page_description = t("hub.genre_instrument_description",
      genre: @genre_name, instrument: @instrument_name, count: @total_count)
  end

  private

  def set_page_params
    @sort = params[:sort] || "popularity"
  end

  def apply_sorting(scores)
    case @sort
    when "popularity" then scores.order_by_popularity
    when "rating" then scores.order_by_rating
    when "newest" then scores.order_by_newest
    when "title" then scores.order_by_title
    when "composer" then scores.order_by_composer
    else scores.order_by_popularity
    end
  end

  # Cached index methods - read from cache, fallback to building
  # Job refreshes daily at 4am; 1.day expiry ensures fallback data doesn't persist forever
  def composers_with_counts
    Rails.cache.fetch("hub/composers", expires_in: 1.day) { build_composers_with_counts }
  end

  def genres_with_counts
    Rails.cache.fetch("hub/genres", expires_in: 1.day) { build_genres_with_counts }
  end

  def instruments_with_counts
    Rails.cache.fetch("hub/instruments", expires_in: 1.day) { build_instruments_with_counts }
  end

  def voicings_with_counts
    Rails.cache.fetch("hub/voicings", expires_in: 1.day) { build_voicings_with_counts }
  end

  # Slug lookups - O(n) scan of cached array, but array is small (~1000 items max)
  def find_composer_by_slug(slug)
    composers_with_counts.find { |c| c[:slug] == slug }&.dig(:name)
  end

  def find_composers_by_slug(slug)
    name = find_composer_by_slug(slug)
    name ? [name] : []
  end

  def find_genre_by_slug(slug)
    genres_with_counts.find { |g| g[:slug] == slug }&.dig(:name)
  end

  def find_instrument_by_slug(slug)
    instruments_with_counts.find { |i| i[:slug] == slug }&.dig(:name)
  end

  def find_voicing_by_slug(slug)
    voicings_with_counts.find { |v| v[:slug] == slug }&.dig(:name)
  end

  # Build methods - expensive, only called on cache miss
  def build_composers_with_counts
    valid_composers = ComposerMapping.normalizable.pluck(:normalized_name).uniq
    composer_counts = Score.where(composer: valid_composers).group(:composer).count

    composer_counts
      .select { |_, count| count >= THRESHOLD }
      .sort_by { |_, count| -count }
      .map { |name, count| { name: name, slug: name.parameterize, count: count } }
  end

  def build_genres_with_counts
    genre_counts = Hash.new(0)
    Score.where.not(genres: [nil, ""]).pluck(:genres).each do |genres_str|
      genres_str.split("-").map(&:strip).reject(&:blank?).each do |genre|
        genre_counts[genre] += 1
      end
    end

    genre_counts
      .select { |_, count| count >= THRESHOLD }
      .sort_by { |_, count| -count }
      .map { |name, count| { name: name, slug: name.parameterize, count: count } }
  end

  def build_instruments_with_counts
    instrument_counts = Hash.new(0)
    Score.where.not(instruments: [nil, ""]).pluck(:instruments).each do |instruments_str|
      instruments_str.split(/[;,]/).map(&:strip).reject(&:blank?).each do |instrument|
        normalized = instrument.gsub(/\s*\(.*\)/, "").strip.downcase
        instrument_counts[normalized] += 1
      end
    end

    instrument_counts
      .select { |_, count| count >= THRESHOLD }
      .sort_by { |_, count| -count }
      .map { |name, count| { name: name.titleize, slug: name.parameterize, count: count } }
  end

  def build_voicings_with_counts
    Score.where.not(voicing: [nil, ""])
         .group(:voicing)
         .count
         .select { |_, count| count >= THRESHOLD }
         .sort_by { |_, count| -count }
         .map { |name, count| { name: name, slug: name.parameterize, count: count } }
  end

  def scores_by_instrument(instrument_name)
    Score.where("LOWER(instruments) LIKE ?", "%#{instrument_name.downcase}%")
  end

  def scores_by_instrument_query(scope, instrument_name)
    scope.where("LOWER(instruments) LIKE ?", "%#{instrument_name.downcase}%")
  end

  def scores_by_voicing(voicing_name)
    Score.where(voicing: voicing_name)
  end

  def not_found
    raise ActionController::RoutingError, "Not Found"
  end
end
