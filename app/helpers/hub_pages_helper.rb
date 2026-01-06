# frozen_string_literal: true

module HubPagesHelper
  # Translates a hub item name using I18n
  # Falls back to the English name if no translation exists
  #
  # @param type [Symbol, String] :genres, :instruments, or :periods
  # @param item [Hash] Hub item with :name and :slug keys
  # @return [String] Translated name
  def translate_hub_name(type, item)
    key = item[:slug].to_s.underscore
    I18n.t("hub.#{type}.#{key}", default: item[:name])
  end

  # Icon mappings for hub index pages
  INSTRUMENT_ICONS = {
    /piano/ => "🎹",
    /violin|viola|fiddle|cello|bass|string/ => "🎻",
    /guitar/ => "🎸",
    /flute|clarinet|oboe|bassoon|recorder|woodwind/ => "🎵",
    /trumpet|trombone|horn|tuba|brass/ => "🎺",
    /drum|percussion|timpani/ => "🥁",
    /organ/ => "⛪",
    /harp/ => "🪕",
    /voice|choir|soprano|alto|tenor|baritone|mezzo|a cappella/ => "🎤",
    /orchestra/ => "🎼",
    /saxophone|sax/ => "🎷",
    /continuo/ => "🎹"
  }.freeze

  GENRE_ICONS = {
    /classical|baroque|romantic/ => "🎻",
    /jazz/ => "🎷",
    /folk/ => "🪕",
    /rock|pop|metal/ => "🎸",
    /choral|sacred|religious|hymn|mass|motet/ => "⛪",
    /opera|aria/ => "🎭",
    /electronic|synth/ => "🎛️",
    /blues/ => "🎺",
    /country|western/ => "🤠",
    /latin|salsa|tango/ => "💃",
    /world|ethnic/ => "🌍",
    /soundtrack|film|cinema/ => "🎬",
    /christmas|carol|holiday/ => "🎄",
    /wedding|love|romance/ => "💒",
    /march|military/ => "🎖️",
    /dance|waltz|polka/ => "💃",
    /lullaby|children/ => "🧒",
    /medieval|renaissance/ => "🏰",
    /modern|contemporary|20th|21st/ => "🎹"
  }.freeze

  DEFAULT_ICONS = {
    instrument: "🎵",
    genre: "🎼"
  }.freeze

  # Returns an emoji icon for an instrument name
  def instrument_icon(name)
    find_icon(name, INSTRUMENT_ICONS, DEFAULT_ICONS[:instrument])
  end

  # Returns an emoji icon for a genre name
  def genre_icon(name)
    find_icon(name, GENRE_ICONS, DEFAULT_ICONS[:genre])
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

  def find_icon(name, mapping, default)
    return default if name.blank?

    downcased = name.to_s.downcase
    mapping.each do |pattern, icon|
      return icon if downcased.match?(pattern)
    end
    default
  end
end
