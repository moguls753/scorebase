class HubPagesController < ApplicationController
  THRESHOLDS = {
    composer: 12,
    genre: 20,
    instrument: 15,
    voicing: 20
  }.freeze

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
    @scores = apply_sorting(@scores)
    @scores = @scores.page(params[:page])
    @total_count = Score.where(composer: @composer_names).count

    @page_title = t("hub.composer_page_title", name: @composer_name)
    @page_description = t("hub.composer_page_description", name: @composer_name, count: @total_count)
  end

  def genre
    @genre_name = find_genre_by_slug(params[:slug])
    not_found unless @genre_name

    @scores = Score.by_genre(@genre_name)
    @scores = apply_sorting(@scores)
    @scores = @scores.page(params[:page])
    @total_count = Score.by_genre(@genre_name).count

    @page_title = t("hub.genre_page_title", name: @genre_name)
    @page_description = t("hub.genre_page_description", name: @genre_name, count: @total_count)
  end

  def instrument
    @instrument_name = find_instrument_by_slug(params[:slug])
    not_found unless @instrument_name

    @scores = scores_by_instrument(@instrument_name)
    @scores = apply_sorting(@scores)
    @scores = @scores.page(params[:page])
    @total_count = scores_by_instrument(@instrument_name).count

    @page_title = t("hub.instrument_page_title", name: @instrument_name)
    @page_description = t("hub.instrument_page_description", name: @instrument_name, count: @total_count)
  end

  def voicing
    @voicing_name = find_voicing_by_slug(params[:slug])
    not_found unless @voicing_name

    @scores = scores_by_voicing(@voicing_name)
    @scores = apply_sorting(@scores)
    @scores = @scores.page(params[:page])
    @total_count = scores_by_voicing(@voicing_name).count

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

    not_found if @total_count < THRESHOLDS[:composer]

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

    not_found if @total_count < THRESHOLDS[:genre]

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

  def composers_with_counts
    cache = AppSetting.fetch("composer_cache", {})
    valid_composers = cache.values.compact.uniq

    composer_counts = Score.where(composer: valid_composers)
                           .group(:composer)
                           .count

    by_slug = Hash.new { |h, k| h[k] = { names: [], total: 0 } }
    composer_counts.each do |name, count|
      slug = name.parameterize
      by_slug[slug][:names] << { name: name, count: count }
      by_slug[slug][:total] += count
    end

    by_slug
      .select { |_, data| data[:total] >= THRESHOLDS[:composer] }
      .sort_by { |_, data| -data[:total] }
      .map do |slug, data|
        best_name = data[:names].max_by { |n| n[:count] }[:name]
        { name: best_name, slug: slug, count: data[:total] }
      end
  end

  def genres_with_counts
    genre_counts = Hash.new(0)
    Score.where.not(genres: [nil, ""]).pluck(:genres).each do |genres_str|
      genres_str.split("-").map(&:strip).reject(&:blank?).each do |genre|
        genre_counts[genre] += 1
      end
    end

    genre_counts
      .select { |_, count| count >= THRESHOLDS[:genre] }
      .sort_by { |_, count| -count }
      .map { |name, count| { name: name, slug: name.parameterize, count: count } }
  end

  def instruments_with_counts
    instrument_counts = Hash.new(0)
    Score.where.not(instruments: [nil, ""]).pluck(:instruments).each do |instruments_str|
      instruments_str.split(/[;,]/).map(&:strip).reject(&:blank?).each do |instrument|
        normalized = instrument.gsub(/\s*\(.*\)/, "").strip.downcase
        instrument_counts[normalized] += 1
      end
    end

    instrument_counts
      .select { |_, count| count >= THRESHOLDS[:instrument] }
      .sort_by { |_, count| -count }
      .map { |name, count| { name: name.titleize, slug: name.parameterize, count: count } }
  end

  def voicings_with_counts
    Score.where.not(voicing: [nil, ""])
         .group(:voicing)
         .count
         .select { |_, count| count >= THRESHOLDS[:voicing] }
         .sort_by { |_, count| -count }
         .map { |name, count| { name: name, slug: name.parameterize, count: count } }
  end

  def find_composer_by_slug(slug)
    Score.where.not(composer: [nil, ""])
         .distinct
         .pluck(:composer)
         .find { |name| name.parameterize == slug }
  end

  def find_composers_by_slug(slug)
    Score.where.not(composer: [nil, ""])
         .group(:composer)
         .count
         .select { |name, _| name.parameterize == slug }
         .sort_by { |_, count| -count }
         .map(&:first)
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
