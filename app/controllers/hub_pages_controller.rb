# frozen_string_literal: true

class HubPagesController < ApplicationController
  before_action :set_sort

  # Index pages
  def composers_index
    @composers = HubDataBuilder.composers
    set_index_meta(:composers)
  end

  def genres_index
    @genres = localize_hub_items(:genres, HubDataBuilder.genres)
    set_index_meta(:genres)
  end

  def instruments_index
    @instruments = localize_hub_items(:instruments, HubDataBuilder.instruments)
    set_index_meta(:instruments)
  end

  def periods_index
    @periods = HubDataBuilder.periods
    set_index_meta(:periods)
  end

  # Detail pages
  def composer
    @composer_name = find_or_404(:composers, params[:slug])

    # Base scope for this composer
    base_scope = Score.where(composer: @composer_name)

    # Apply filters
    filtered_scope = base_scope
    filtered_scope = filtered_scope.by_instrument(params[:instrument]) if params[:instrument].present?
    filtered_scope = filtered_scope.by_genre(params[:genre]) if params[:genre].present?

    # Apply scoped search
    filtered_scope = filtered_scope.search_by_title(params[:q]) if params[:q].present?

    # Counts
    @total_count = base_scope.count
    @filtered_count = filtered_scope.count

    # Paginate
    @scores = paginate_filtered(filtered_scope)

    # Dynamic filter options (faceted)
    @filter_options = build_composer_filter_options(base_scope, params)

    # Other metadata
    @composer_period = base_scope.where.not(period: [nil, ""])
                            .pick(:period)
    set_detail_meta(:composer, @composer_name)
  end

  def genre
    @genre_name = find_or_404(:genres, params[:slug])

    # Base scope for this genre
    base_scope = Score.by_genre(@genre_name)

    # Apply filters
    filtered_scope = base_scope
    filtered_scope = filtered_scope.by_instrument(params[:instrument]) if params[:instrument].present?
    filtered_scope = filtered_scope.where(composer: composer_name_from_slug(params[:composer])) if params[:composer].present?

    # Apply scoped search
    filtered_scope = filtered_scope.search_by_title(params[:q]) if params[:q].present?

    # Counts
    @total_count = base_scope.count
    @filtered_count = filtered_scope.count

    # Paginate
    @scores = paginate_filtered(filtered_scope)

    # Dynamic filter options (faceted)
    @filter_options = build_genre_filter_options(base_scope, params)

    set_detail_meta(:genre, @genre_name)
  end

  def instrument
    @instrument_name = find_or_404(:instruments, params[:slug])
    @scores = paginate(Score.by_instrument(@instrument_name))
    @top_periods = HubDataBuilder.periods_for_instrument(@instrument_name)
    set_detail_meta(:instrument, @instrument_name)
  end

  def period
    @period_name = find_or_404(:periods, params[:slug])
    @scores = paginate(Score.by_period(@period_name))
    @top_instruments = HubDataBuilder.top_instruments_for(:period, @period_name)
    set_detail_meta(:period, @period_name)
  end

  # Combined pages
  def composer_instrument
    @composer_name = find_or_404(:composers, params[:composer_slug])
    @instrument_name = find_or_404(:instruments, params[:instrument_slug])

    @scores = paginate(Score.where(composer: @composer_name).by_instrument(@instrument_name))
    not_found if @total_count < HubDataBuilder::THRESHOLD

    @page_title = t("hub.composer_instrument_title", composer: @composer_name, instrument: @instrument_name)
    @page_description = t("hub.composer_instrument_description",
      composer: @composer_name, instrument: @instrument_name, count: @total_count)
  end

  def genre_instrument
    @genre_name = find_or_404(:genres, params[:genre_slug])
    @instrument_name = find_or_404(:instruments, params[:instrument_slug])

    @scores = paginate(Score.by_genre(@genre_name).by_instrument(@instrument_name))
    not_found if @total_count < HubDataBuilder::THRESHOLD

    @page_title = t("hub.genre_instrument_title", genre: @genre_name, instrument: @instrument_name)
    @page_description = t("hub.genre_instrument_description",
      genre: @genre_name, instrument: @instrument_name, count: @total_count)
  end

  def period_instrument
    @period_name = find_or_404(:periods, params[:period_slug])
    @instrument_name = find_or_404(:instruments, params[:instrument_slug])

    @scores = paginate(Score.by_period(@period_name).by_instrument(@instrument_name))
    not_found if @total_count < HubDataBuilder::THRESHOLD

    @page_title = t("hub.period_instrument_title", period: @period_name, instrument: @instrument_name)
    @page_description = t("hub.period_instrument_description",
      period: @period_name, instrument: @instrument_name, count: @total_count)
  end

  private

  def set_sort
    @sort = params[:sort] || "popularity"
  end

  def find_or_404(type, slug)
    HubDataBuilder.find_by_slug(type, slug) || not_found
  end

  def paginate(scope)
    sorted = apply_sorting(scope)
    @total_count = sorted.count
    sorted.with_attached_thumbnail_image.page(params[:page]).without_count
  end

  # Paginate without setting @total_count (used when counts are set separately)
  def paginate_filtered(scope)
    sorted = apply_sorting(scope)
    sorted.with_attached_thumbnail_image.page(params[:page]).without_count
  end

  # Build filter options for composer page using efficient DISTINCT queries
  # Returns available options (without counts) based on current filters
  # Only 3 queries total instead of ~137
  def build_composer_filter_options(base_scope, current_params)
    # Apply search filter to base scope (affects all filter options)
    scope = base_scope
    scope = scope.search_by_title(current_params[:q]) if current_params[:q].present?

    {
      instruments: available_instruments(scope, current_params),
      genres: available_genres(scope, current_params)
    }
  end

  # Get available instruments using DISTINCT query (1 query)
  def available_instruments(base_scope, current_params)
    # Apply other filters (not instrument) to narrow down options
    scope = base_scope
    scope = scope.by_genre(current_params[:genre]) if current_params[:genre].present?

    # Single query: get all distinct instrument strings
    distinct_values = scope.where.not(instruments: [nil, ""]).distinct.pluck(:instruments)

    # Filter to valid instruments that appear in any string
    HubDataBuilder::VALID_INSTRUMENTS.filter_map do |instrument|
      next unless distinct_values.any? { |str| str.downcase.include?(instrument.downcase) }
      { name: instrument.titleize, slug: instrument.parameterize }
    end
  end

  # Get available genres using DISTINCT query (1 query)
  def available_genres(base_scope, current_params)
    scope = base_scope
    scope = scope.by_instrument(current_params[:instrument]) if current_params[:instrument].present?

    distinct_values = scope.where.not(genre: [nil, ""]).distinct.pluck(:genre)

    HubDataBuilder::VALID_GENRES.filter_map do |genre|
      # Genre field may contain the genre directly or as part of a list
      next unless distinct_values.any? { |str| str.downcase.include?(genre.downcase) }
      { name: genre, slug: genre.parameterize }
    end
  end

  # Build filter options for genre page using efficient DISTINCT queries
  def build_genre_filter_options(base_scope, current_params)
    # Apply search filter to base scope (affects all filter options)
    scope = base_scope
    scope = scope.search_by_title(current_params[:q]) if current_params[:q].present?

    {
      instruments: available_instruments_for_genre(scope, current_params),
      composers: available_composers_for_genre(scope, current_params)
    }
  end

  # Get available instruments for genre page (1 query)
  def available_instruments_for_genre(base_scope, current_params)
    scope = base_scope
    scope = scope.where(composer: composer_name_from_slug(current_params[:composer])) if current_params[:composer].present?

    distinct_values = scope.where.not(instruments: [nil, ""]).distinct.pluck(:instruments)

    HubDataBuilder::VALID_INSTRUMENTS.filter_map do |instrument|
      next unless distinct_values.any? { |str| str.downcase.include?(instrument.downcase) }
      { name: instrument.titleize, slug: instrument.parameterize }
    end
  end

  # Get available composers for genre page (1 query)
  # Returns top composers by score count within this genre
  def available_composers_for_genre(base_scope, current_params)
    scope = base_scope
    scope = scope.by_instrument(current_params[:instrument]) if current_params[:instrument].present?

    # Get top composers with their counts, limited to reasonable dropdown size
    scope.where.not(composer: [nil, ""])
         .group(:composer)
         .order(Arel.sql("COUNT(*) DESC"))
         .limit(50)
         .pluck(:composer)
         .map { |name| { name: name, slug: name.parameterize } }
  end

  # Convert composer slug back to canonical name
  def composer_name_from_slug(slug)
    return nil if slug.blank?
    # Look up in hub data to get exact name
    HubDataBuilder.find_by_slug(:composers, slug)
  end

  # Convert period slug to canonical name (e.g., "baroque" -> "Baroque")
  def period_name_from_slug(slug)
    return nil if slug.blank?
    HubDataBuilder::PERIOD_ORDER.find { |p| p.parameterize == slug }
  end

  def apply_sorting(scope)
    case @sort
    when "popularity" then scope.order_by_popularity
    when "newest"     then scope.order_by_newest
    when "title"      then scope.order_by_title
    when "composer"   then scope.order_by_composer
    else scope.order_by_popularity
    end
  end

  def set_index_meta(type)
    data = instance_variable_get("@#{type}")
    @page_title = t("hub.#{type}_title")
    @page_description = t("hub.#{type}_description", count: data.size)
  end

  def set_detail_meta(type, name)
    @page_title = t("hub.#{type}_page_title", name: name)
    @page_description = t("hub.#{type}_page_description", name: name, count: @total_count)
  end

  def not_found
    raise ActionController::RoutingError, "Not Found"
  end

  # Adds translated display names and sorts by locale
  def localize_hub_items(type, items)
    items.map do |item|
      item.merge(display_name: helpers.translate_hub_name(type, item))
    end.sort_by { |item| item[:display_name].downcase }
  end
end
