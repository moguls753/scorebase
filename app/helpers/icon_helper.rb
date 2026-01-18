# frozen_string_literal: true

# Lucide Icon helper for ScoreBase
# Uses lucide-rails gem for consistent, professional icons
# Total: 18 icons (4 Navigation + 7 Periods + 7 Genres)
module IconHelper
  # Navigation category icons
  NAVIGATION_ICONS = {
    composers: "user",
    genres: "music",
    instruments: "guitar",
    periods: "hourglass"
  }.freeze

  # Period icons - representing musical eras
  PERIOD_ICONS = {
    medieval: "castle",
    renaissance: "landmark",
    baroque: "crown",
    classical: "columns",
    romantic: "heart",
    impressionist: "cloud",
    modern: "zap"
  }.freeze

  # Genre icons - representing musical styles
  GENRE_ICONS = {
    sacred: "church",
    jazz: "music-2",
    folk: "guitar",
    opera: "drama",
    march: "flag",
    dance: "footprints",
    default: "music"
  }.freeze

  # Pattern matching for genres
  GENRE_PATTERNS = [
    [/sacred|religious|hymn|mass|motet|choral|choir/, :sacred],
    [/jazz/, :jazz],
    [/folk|traditional/, :folk],
    [/opera|aria/, :opera],
    [/march|military/, :march],
    [/dance|waltz|polka|tango/, :dance]
  ].freeze

  # Pattern matching for periods
  PERIOD_PATTERNS = [
    [/medieval/, :medieval],
    [/renaissance/, :renaissance],
    [/baroque/, :baroque],
    [/classical/, :classical],
    [/romantic/, :romantic],
    [/impressionist/, :impressionist],
    [/modern|contemporary|20th|21st/, :modern]
  ].freeze

  def period_svg_icon(name, size: 18, html_class: nil)
    icon_name = resolve_period_icon(name)
    lucide_icon(icon_name, size: size, class: html_class)
  end

  def genre_svg_icon(name, size: 18, html_class: nil)
    icon_name = resolve_genre_icon(name)
    lucide_icon(icon_name, size: size, class: html_class)
  end

  def navigation_svg_icon(category, size: 20, html_class: nil)
    key = category.to_s.downcase.to_sym
    icon_name = NAVIGATION_ICONS[key] || "music"
    lucide_icon(icon_name, size: size, class: html_class)
  end

  # Deprecated: Instrument icons removed - use text-only display
  # Returns nil to signal callers should use text instead
  def instrument_svg_icon(_name, size: 18, html_class: nil)
    nil
  end

  private

  def resolve_period_icon(name)
    return PERIOD_ICONS[:classical] if name.blank?

    normalized = name.to_s.downcase
    key = find_pattern_match(normalized, PERIOD_PATTERNS) || :classical
    PERIOD_ICONS[key]
  end

  def resolve_genre_icon(name)
    return GENRE_ICONS[:default] if name.blank?

    normalized = name.to_s.downcase

    # Check if it's a period name (share icons)
    if PERIOD_ICONS.key?(normalized.to_sym)
      return PERIOD_ICONS[normalized.to_sym]
    end

    key = find_pattern_match(normalized, GENRE_PATTERNS) || :default
    GENRE_ICONS[key]
  end

  def find_pattern_match(text, patterns)
    patterns.find { |pattern, _| text.match?(pattern) }&.last
  end
end
