# frozen_string_literal: true

module HubPagesHelper
  # Filter parameters for composer page
  COMPOSER_FILTER_PARAMS = %i[instrument genre].freeze

  # Count active filters for composer page
  def composer_active_filters_count
    COMPOSER_FILTER_PARAMS.count { |param| params[param].present? }
  end

  # Generate hidden fields for composer filter params to preserve state across forms
  def composer_filter_hidden_fields(form)
    safe_join(COMPOSER_FILTER_PARAMS.map { |param| form.hidden_field(param, value: params[param]) })
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
end
