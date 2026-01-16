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
    @scores = paginate(Score.where(composer: @composer_name))
    @composer_period = Score.where(composer: @composer_name)
                            .where.not(period: [nil, ""])
                            .pick(:period)
    set_detail_meta(:composer, @composer_name)
  end

  def genre
    @genre_name = find_or_404(:genres, params[:slug])
    @scores = paginate(Score.by_genre(@genre_name))
    set_detail_meta(:genre, @genre_name)
  end

  def instrument
    @instrument_name = find_or_404(:instruments, params[:slug])
    @scores = paginate(Score.by_instrument(@instrument_name))
    set_detail_meta(:instrument, @instrument_name)
  end

  def period
    @period_name = find_or_404(:periods, params[:slug])
    @scores = paginate(Score.by_period(@period_name))
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
