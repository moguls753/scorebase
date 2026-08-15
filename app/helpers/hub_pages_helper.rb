# frozen_string_literal: true

module HubPagesHelper
  # Filter parameters for composer/artist pages (same filters)
  COMPOSER_FILTER_PARAMS = %i[instrument genre].freeze

  # Filter parameters for genre page
  GENRE_FILTER_PARAMS = %i[instrument composer].freeze

  # Filter parameters for period page
  PERIOD_FILTER_PARAMS = %i[instrument composer genre].freeze

  # Filter parameters for instrument page (also used by instrument+difficulty pages)
  INSTRUMENT_FILTER_PARAMS = %i[composer genre].freeze

  # Count active filters for composer page
  def composer_active_filters_count
    COMPOSER_FILTER_PARAMS.count { |param| params[param].present? }
  end

  # Generate hidden fields for composer filter params to preserve state across forms
  def composer_filter_hidden_fields(form)
    safe_join(COMPOSER_FILTER_PARAMS.map { |param| form.hidden_field(param, value: params[param]) })
  end

  # Artist uses same filters as composer
  alias_method :artist_active_filters_count, :composer_active_filters_count
  alias_method :artist_filter_hidden_fields, :composer_filter_hidden_fields

  # Count active filters for genre page
  def genre_active_filters_count
    GENRE_FILTER_PARAMS.count { |param| params[param].present? }
  end

  # Generate hidden fields for genre filter params to preserve state across forms
  def genre_filter_hidden_fields(form)
    safe_join(GENRE_FILTER_PARAMS.map { |param| form.hidden_field(param, value: params[param]) })
  end

  # Ensemble page uses the same instrument+composer filters as genre
  alias_method :ensemble_active_filters_count, :genre_active_filters_count
  alias_method :ensemble_filter_hidden_fields, :genre_filter_hidden_fields

  # Count active filters for period page
  def period_active_filters_count
    PERIOD_FILTER_PARAMS.count { |param| params[param].present? }
  end

  # Generate hidden fields for period filter params to preserve state across forms
  def period_filter_hidden_fields(form)
    safe_join(PERIOD_FILTER_PARAMS.map { |param| form.hidden_field(param, value: params[param]) })
  end

  # Count active filters for instrument page
  def instrument_active_filters_count
    INSTRUMENT_FILTER_PARAMS.count { |param| params[param].present? }
  end

  # Generate hidden fields for instrument filter params to preserve state across forms
  def instrument_filter_hidden_fields(form)
    safe_join(INSTRUMENT_FILTER_PARAMS.map { |param| form.hidden_field(param, value: params[param]) })
  end

  # Translates a hub item name using I18n
  # Falls back to the English name if no translation exists
  #
  # @param type [Symbol, String] :genres, :instruments, or :periods
  # @param item [Hash] Hub item with :name and :slug keys
  # @return [String] Translated name
  def translate_hub_name(type, item)
    key = item[:slug].to_s.underscore
    # Use singular_name keys to avoid conflict with hub.periods string etc.
    translation_key = "hub.#{type.to_s.singularize}_names.#{key}"
    I18n.t(translation_key, default: item[:name])
  end

  # Scopes match case-insensitively, so ?instrument=Organ filters yet never equals the "organ" option value
  def filter_options_for_select(pairs, selected)
    match = pairs.find { |_label, value| value.to_s.parameterize == selected.to_s.parameterize }
    options_for_select(pairs, match ? match.last : selected)
  end

  # One slot more when a chip is marked current, so marking never costs an outbound link
  def instrument_link_items(type, name, active_slug)
    items = HubDataBuilder.top_instruments_for(type, name, limit: active_slug ? 7 : 6)
    marked = items.any? { |item| item[:slug] == active_slug }
    items = items.first(6) unless marked
    items if items.count { |item| item[:slug] != active_slug } >= (marked ? 2 : 3)
  end

  # by_instrument matches any part, so a "Choir" card on an organ page is correct, not a filter bug
  def instrument_part_badge(score, instrument_name, label = nil)
    return if instrument_name.blank?

    needle = instrument_name.downcase
    return if instrument_mentioned?(score.primary_instrument, needle)
    return unless instrument_mentioned?(score.instruments, needle)

    t("score.includes_instrument", instrument: label.presence || instrument_name)
  end

  # Normalizes the first letter for grouping, handling non-alphabetic chars
  # Returns the letter (A-Z) or "#" for numbers/symbols
  # Accented letters are normalized: "Ääkkönen" -> "A", "Österreich" -> "O"
  def hub_group_letter(name)
    return "#" if name.blank?

    first_char = name.first.upcase
    # Normalize accented characters: Ä -> A, Ö -> O, É -> E, etc.
    normalized = first_char.unicode_normalize(:nfkd).gsub(/[\u0300-\u036f]/, "")
    normalized.match?(/[A-Z]/) ? normalized : "#"
  end

  # Groups items by first letter, with non-alphabetic grouped under "#"
  # Returns sorted array of [letter, items] pairs with "#" always last
  def hub_group_by_letter(items, name_key: :name)
    grouped = items.group_by { |item| hub_group_letter(item[name_key]) }

    # Sort alphabetically, but put "#" at the end
    grouped.sort_by { |letter, _| letter == "#" ? "ZZZ" : letter }
  end

  # Calculates animation delay for staggered card loading
  # Caps at 30 items to avoid excessive delays
  def hub_card_delay(index, delay_ms: 20)
    return 0 if index.nil? || index >= 30

    index * delay_ms
  end

  # Returns style attribute for animation delay, or nil if no delay
  def hub_card_style(index, delay_ms: 20)
    delay = hub_card_delay(index, delay_ms: delay_ms)
    delay.positive? ? "animation-delay: #{delay}ms" : nil
  end

  private

  def instrument_mentioned?(field, needle)
    haystack = HubDataBuilder::INSTRUMENT_DECOYS.fetch(needle, []).inject(field.to_s.downcase) { |acc, decoy| acc.gsub(decoy, " ") }
    haystack.include?(needle)
  end
end
