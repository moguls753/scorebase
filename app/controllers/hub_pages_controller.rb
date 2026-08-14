# frozen_string_literal: true

class HubPagesController < ApplicationController
  before_action :set_sort

  # Index pages
  def composers_index
    @composers = HubDataBuilder.composers
    set_index_meta(:composers)
  end

  def artists_index
    @artists = HubDataBuilder.artists
    set_index_meta(:artists)
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

  def ensembles_index
    @ensembles = localize_hub_items(:ensembles, HubDataBuilder.ensembles)
    @ensemble_groups = HubDataBuilder.ensemble_groups.transform_values do |items|
      localize_hub_items(:ensembles, items, sort: false)
    end
    set_index_meta(:ensembles)
  end

  # Detail pages
  def composer
    @composer_name = find_or_404(:composers, params[:slug])

    # Base scope for this composer
    base_scope = Score.active.where(composer: @composer_name)

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

  def artist
    @artist_name = find_or_404(:artists, params[:slug])

    # Base scope for this artist (SMD scores only)
    base_scope = Score.active.where(artist: @artist_name)

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
    @filter_options = build_artist_filter_options(base_scope, params)

    set_detail_meta(:artist, @artist_name)
  end

  def genre
    @genre_name = find_or_404(:genres, params[:slug])

    # Base scope for this genre
    base_scope = Score.active.by_genre(@genre_name)

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

    @genre_display_name = localized_hub_name(:genres, params[:slug], @genre_name)
    set_detail_meta(:genre, @genre_display_name)
  end

  def instrument
    @instrument_name = find_or_404(:instruments, params[:slug])

    # Base scope for this instrument
    base_scope = Score.active.by_instrument(@instrument_name)

    # Apply filters
    filtered_scope = base_scope
    filtered_scope = filtered_scope.where(composer: composer_name_from_slug(params[:composer])) if params[:composer].present?
    filtered_scope = filtered_scope.by_genre(params[:genre]) if params[:genre].present?

    # Apply scoped search
    filtered_scope = filtered_scope.search_by_title(params[:q]) if params[:q].present?

    # Counts
    @total_count = base_scope.count
    @filtered_count = filtered_scope.count

    # Paginate
    @scores = paginate_filtered(filtered_scope)

    # Dynamic filter options (faceted)
    @filter_options = build_instrument_filter_options(base_scope, params)

    @instrument_display_name = localized_hub_name(:instruments, params[:slug], @instrument_name)
    set_detail_meta(:instrument, @instrument_display_name)
  end

  def period
    @period_name = find_or_404(:periods, params[:slug])

    # Base scope for this period
    base_scope = Score.active.by_period(@period_name)

    # Apply filters
    filtered_scope = base_scope
    filtered_scope = filtered_scope.by_instrument(params[:instrument]) if params[:instrument].present?
    filtered_scope = filtered_scope.where(composer: composer_name_from_slug(params[:composer])) if params[:composer].present?
    filtered_scope = filtered_scope.by_genre(params[:genre]) if params[:genre].present?

    # Apply scoped search
    filtered_scope = filtered_scope.search_by_title(params[:q]) if params[:q].present?

    # Counts
    @total_count = base_scope.count
    @filtered_count = filtered_scope.count

    # Paginate
    @scores = paginate_filtered(filtered_scope)

    # Dynamic filter options (faceted)
    @filter_options = build_period_filter_options(base_scope, params)

    @period_display_name = localized_hub_name(:periods, params[:slug], @period_name)
    set_detail_meta(:period, @period_display_name)
  end

  def ensemble
    @ensemble_name = find_or_404(:ensembles, params[:slug])
    @ensemble_display_name = helpers.translate_hub_name(
      :ensembles, { slug: params[:slug], name: @ensemble_name }
    )

    # Base scope for this ensemble category — deduplicated so each card is one
    # arrangement (rep or ungrouped), not a part dump.
    base_scope = Score.active.where(smd_category: @ensemble_name).deduplicate_arrangements

    # Apply filters
    filtered_scope = base_scope
    filtered_scope = filtered_scope.by_instrument(params[:instrument]) if params[:instrument].present?
    # Ensemble composers are SMD arrangers stored "First Last" — absent from the
    # classical composer hub, so resolve the slug against this page's own scope
    # (composer_name_from_slug would return nil -> where(composer: nil) -> empty page).
    if params[:composer].present? && (name = composer_in_scope(base_scope, params[:composer]))
      filtered_scope = filtered_scope.where(composer: name)
    end

    # Apply scoped search
    filtered_scope = filtered_scope.search_by_title(params[:q]) if params[:q].present?

    # Counts
    @total_count = base_scope.count
    @filtered_count = filtered_scope.count

    # Paginate
    @scores = paginate_filtered(filtered_scope)

    # Dynamic filter options (faceted)
    @filter_options = build_ensemble_filter_options(base_scope, params)

    set_detail_meta(:ensemble, @ensemble_display_name)
  end

  # Combined pages
  def composer_instrument
    @composer_name = find_or_404(:composers, params[:composer_slug])
    @instrument_name = find_or_404(:instruments, params[:instrument_slug])

    @scores = paginate(Score.active.where(composer: @composer_name).by_instrument(@instrument_name))
    not_found if @total_count < HubDataBuilder::THRESHOLD

    @instrument_display_name = localized_hub_name(:instruments, params[:instrument_slug], @instrument_name)
    @page_title = t("hub.composer_instrument_title", composer: @composer_name, instrument: @instrument_display_name)
    @page_description = t("hub.composer_instrument_description",
      composer: @composer_name, instrument: @instrument_display_name, count: @total_count)
  end

  def genre_instrument
    @genre_name = find_or_404(:genres, params[:genre_slug])
    @instrument_name = find_or_404(:instruments, params[:instrument_slug])

    @scores = paginate(Score.active.by_genre(@genre_name).by_instrument(@instrument_name))
    not_found if @total_count < HubDataBuilder::THRESHOLD

    @genre_display_name = localized_hub_name(:genres, params[:genre_slug], @genre_name)
    @instrument_display_name = localized_hub_name(:instruments, params[:instrument_slug], @instrument_name)
    @page_title = t("hub.genre_instrument_title", genre: @genre_display_name, instrument: @instrument_display_name)
    @page_description = t("hub.genre_instrument_description",
      genre: @genre_display_name, instrument: @instrument_display_name, count: @total_count)
  end

  def period_instrument
    @period_name = find_or_404(:periods, params[:period_slug])
    @instrument_name = find_or_404(:instruments, params[:instrument_slug])

    @scores = paginate(Score.active.by_period(@period_name).by_instrument(@instrument_name))
    not_found if @total_count < HubDataBuilder::THRESHOLD

    @period_display_name = localized_hub_name(:periods, params[:period_slug], @period_name)
    @instrument_display_name = localized_hub_name(:instruments, params[:instrument_slug], @instrument_name)
    @page_title = t("hub.period_instrument_title", period: @period_display_name, instrument: @instrument_display_name)
    @page_description = t("hub.period_instrument_description",
      period: @period_display_name, instrument: @instrument_display_name, count: @total_count)
  end

  # Instrument + Difficulty pages (SEO landing pages like /piano/beginners)
  def instrument_difficulty
    @instrument_name = find_or_404(:instruments, params[:instrument_slug])
    @difficulty_slug = params[:difficulty_slug]
    @difficulty_name = HubDataBuilder::VALID_DIFFICULTIES[@difficulty_slug]
    not_found unless @difficulty_name

    # Base scope for this instrument + difficulty
    base_scope = Score.active.by_instrument(@instrument_name).by_difficulty(@difficulty_slug)

    # Apply filters
    filtered_scope = base_scope
    filtered_scope = filtered_scope.where(composer: composer_name_from_slug(params[:composer])) if params[:composer].present?
    filtered_scope = filtered_scope.by_genre(params[:genre]) if params[:genre].present?

    # Apply scoped search
    filtered_scope = filtered_scope.search_by_title(params[:q]) if params[:q].present?

    # Counts
    @total_count = base_scope.count
    @filtered_count = filtered_scope.count

    # 404 if combination has too few scores
    not_found if @total_count < HubDataBuilder::THRESHOLD

    # Paginate
    @scores = paginate_filtered(filtered_scope)

    # Dynamic filter options (faceted)
    @filter_options = build_instrument_difficulty_filter_options(base_scope, params)

    set_instrument_difficulty_meta
  end

  # Christmas landing pages
  def christmas
    base_scope = Score.active.christmas
    @scores = paginate(base_scope)
    @christmas_instruments = HubDataBuilder::CHRISTMAS_INSTRUMENTS
    @page_title = t("hub.christmas_title")
    @page_description = t("hub.christmas_description", count: @total_count)
  end

  def christmas_choir
    base_scope = Score.active.christmas.satb_choir

    filtered_scope = base_scope
    filtered_scope = filtered_scope.search_by_title(params[:q]) if params[:q].present?

    @total_count = base_scope.count
    @filtered_count = filtered_scope.count
    @scores = paginate_filtered(filtered_scope)

    @page_title = t("hub.christmas_choir_title")
    @page_description = t("hub.christmas_choir_description", count: @total_count)
  end

  def christmas_instrument
    @instrument_slug = params[:instrument_slug]
    @instrument_name = @instrument_slug.titleize
    @instrument_display_name = localized_hub_name(:instruments, @instrument_slug, @instrument_name)

    base_scope = Score.active.christmas.by_instrument(@instrument_slug)

    @total_count = base_scope.count
    not_found if @total_count < HubDataBuilder::CHRISTMAS_INSTRUMENT_THRESHOLD

    filtered_scope = base_scope
    filtered_scope = filtered_scope.search_by_title(params[:q]) if params[:q].present?

    @filtered_count = filtered_scope.count
    @scores = paginate_filtered(filtered_scope)

    @page_title = t("hub.christmas_instrument_title", instrument: @instrument_name)
    @page_description = t("hub.christmas_instrument_description", instrument: @instrument_name.downcase, count: @total_count)
  end

  private

  def set_sort
    @sort = params[:sort] || "popularity"
  end

  def find_or_404(type, slug)
    HubDataBuilder.find_by_slug(type, slug) || not_found
  end

  def paginate(scope)
    sorted = apply_sorting(scope).deduplicate_arrangements
    result = finalize_pagination(sorted.with_attached_thumbnail_image.page(params[:page]).without_count)
    @total_count = sorted.count
    result
  end

  # Paginate without setting @total_count (used when counts are set separately)
  def paginate_filtered(scope)
    sorted = apply_sorting(scope).deduplicate_arrangements
    finalize_pagination(sorted.with_attached_thumbnail_image.page(params[:page]).without_count)
  end

  # Force-load the paginated relation and 404 when ?page=N>1 returns no rows.
  # Kaminari otherwise silently renders an empty 200, which Google flags as soft 404.
  def finalize_pagination(relation)
    relation.load
    raise ActionController::RoutingError, "Page out of range" if params[:page].to_i > 1 && relation.empty?
    relation
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

  # Artist uses same filter options as composer (instrument + genre)
  alias_method :build_artist_filter_options, :build_composer_filter_options

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

  # Ensemble uses same filter options as genre (instrument + composer)
  alias_method :build_ensemble_filter_options, :build_genre_filter_options

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

  # Build filter options for instrument page using efficient DISTINCT queries
  def build_instrument_filter_options(base_scope, current_params)
    # Apply search filter to base scope (affects all filter options)
    scope = base_scope
    scope = scope.search_by_title(current_params[:q]) if current_params[:q].present?

    {
      composers: available_composers_for_instrument(scope, current_params),
      genres: available_genres_for_instrument(scope, current_params)
    }
  end

  # Get available composers for instrument page (1 query)
  # Returns top composers by score count within this instrument
  def available_composers_for_instrument(base_scope, current_params)
    scope = base_scope
    scope = scope.by_genre(current_params[:genre]) if current_params[:genre].present?

    # Get top composers with their counts, limited to reasonable dropdown size
    scope.where.not(composer: [nil, ""])
         .group(:composer)
         .order(Arel.sql("COUNT(*) DESC"))
         .limit(50)
         .pluck(:composer)
         .map { |name| { name: name, slug: name.parameterize } }
  end

  # Get available genres for instrument page (1 query)
  def available_genres_for_instrument(base_scope, current_params)
    scope = base_scope
    scope = scope.where(composer: composer_name_from_slug(current_params[:composer])) if current_params[:composer].present?

    distinct_values = scope.where.not(genre: [nil, ""]).distinct.pluck(:genre)

    HubDataBuilder::VALID_GENRES.filter_map do |genre|
      next unless distinct_values.any? { |str| str.downcase.include?(genre.downcase) }
      { name: genre, slug: genre.parameterize }
    end
  end

  # Build filter options for period page using efficient DISTINCT queries
  def build_period_filter_options(base_scope, current_params)
    scope = base_scope
    scope = scope.search_by_title(current_params[:q]) if current_params[:q].present?

    {
      instruments: available_instruments_for_period(scope, current_params),
      composers: available_composers_for_period(scope, current_params),
      genres: available_genres_for_period(scope, current_params)
    }
  end

  # Get available instruments for period page (1 query)
  def available_instruments_for_period(base_scope, current_params)
    scope = base_scope
    scope = scope.where(composer: composer_name_from_slug(current_params[:composer])) if current_params[:composer].present?
    scope = scope.by_genre(current_params[:genre]) if current_params[:genre].present?

    distinct_values = scope.where.not(instruments: [nil, ""]).distinct.pluck(:instruments)

    HubDataBuilder::VALID_INSTRUMENTS.filter_map do |instrument|
      next unless distinct_values.any? { |str| str.downcase.include?(instrument.downcase) }
      { name: instrument.titleize, slug: instrument.parameterize }
    end
  end

  # Get available composers for period page (1 query)
  def available_composers_for_period(base_scope, current_params)
    scope = base_scope
    scope = scope.by_instrument(current_params[:instrument]) if current_params[:instrument].present?
    scope = scope.by_genre(current_params[:genre]) if current_params[:genre].present?

    scope.where.not(composer: [nil, ""])
         .group(:composer)
         .order(Arel.sql("COUNT(*) DESC"))
         .limit(50)
         .pluck(:composer)
         .map { |name| { name: name, slug: name.parameterize } }
  end

  # Get available genres for period page (1 query)
  def available_genres_for_period(base_scope, current_params)
    scope = base_scope
    scope = scope.by_instrument(current_params[:instrument]) if current_params[:instrument].present?
    scope = scope.where(composer: composer_name_from_slug(current_params[:composer])) if current_params[:composer].present?

    distinct_values = scope.where.not(genre: [nil, ""]).distinct.pluck(:genre)

    HubDataBuilder::VALID_GENRES.filter_map do |genre|
      next unless distinct_values.any? { |str| str.downcase.include?(genre.downcase) }
      { name: genre, slug: genre.parameterize }
    end
  end

  # Convert composer slug back to canonical name
  def composer_name_from_slug(slug)
    return nil if slug.blank?
    # Look up in hub data to get exact name
    HubDataBuilder.find_by_slug(:composers, slug)
  end

  # Resolve a composer slug against a specific scope's own composers (for hubs
  # whose content isn't in the classical composer hub, e.g. SMD arrangers).
  def composer_in_scope(scope, slug)
    return nil if slug.blank?
    scope.where.not(composer: [ nil, "" ]).distinct.pluck(:composer).find { |c| c.parameterize == slug }
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

  # Scopes must query the canonical English name; anything rendered or put in a
  # title needs the localized one, or a German page reads "Piano" and "Sonata".
  def localized_hub_name(type, slug, name)
    helpers.translate_hub_name(type, { slug: slug, name: name })
  end

  def set_detail_meta(type, name)
    @page_title = t("hub.#{type}_page_title", name: name)
    @page_description = t("hub.#{type}_page_description", name: name, count: @total_count)
  end

  def not_found
    raise ActionController::RoutingError, "Not Found"
  end

  # Build filter options for instrument+difficulty page using efficient DISTINCT queries
  # Uses same filters as instrument page (composer, genre) for consistency
  def build_instrument_difficulty_filter_options(base_scope, current_params)
    scope = base_scope
    scope = scope.search_by_title(current_params[:q]) if current_params[:q].present?

    {
      composers: available_composers_for_instrument_difficulty(scope, current_params),
      genres: available_genres_for_instrument_difficulty(scope, current_params)
    }
  end

  def available_composers_for_instrument_difficulty(base_scope, current_params)
    scope = base_scope
    scope = scope.by_genre(current_params[:genre]) if current_params[:genre].present?

    scope.where.not(composer: [nil, ""])
         .group(:composer)
         .order(Arel.sql("COUNT(*) DESC"))
         .limit(50)
         .pluck(:composer)
         .map { |name| { name: name, slug: name.parameterize } }
  end

  def available_genres_for_instrument_difficulty(base_scope, current_params)
    scope = base_scope
    scope = scope.where(composer: composer_name_from_slug(current_params[:composer])) if current_params[:composer].present?

    distinct_values = scope.where.not(genre: [nil, ""]).distinct.pluck(:genre)

    HubDataBuilder::VALID_GENRES.filter_map do |genre|
      next unless distinct_values.any? { |str| str.downcase.include?(genre.downcase) }
      { name: genre, slug: genre.parameterize }
    end
  end

  def set_instrument_difficulty_meta
    @instrument_display_name = localized_hub_name(:instruments, params[:instrument_slug], @instrument_name)
    difficulty_display = t("difficulty.#{@difficulty_slug}", default: @difficulty_name)
    @page_title = t("hub.instrument_difficulty_title",
      difficulty: difficulty_display,
      instrument: @instrument_display_name)
    @page_description = t("hub.instrument_difficulty_description",
      difficulty: difficulty_display.downcase,
      instrument: @instrument_display_name.downcase,
      count: @total_count)
  end

  def localize_hub_items(type, items, sort: true)
    localized = items.map do |item|
      item.merge(display_name: helpers.translate_hub_name(type, item))
    end
    sort ? localized.sort_by { |item| item[:display_name].downcase } : localized
  end
end
