# frozen_string_literal: true

# Lucide Icon helper for ScoreBase
# Uses lucide-rails gem for consistent, professional icons
module IconHelper
  NAVIGATION_ICONS = {
    composers: "user",
    genres: "music",
    instruments: "guitar",
    periods: "hourglass"
  }.freeze

  PERIOD_ICONS = {
    medieval: "castle",
    renaissance: "landmark",
    baroque: "crown",
    classical: "columns",
    romantic: "heart",
    impressionist: "cloud",
    modern: "zap"
  }.freeze

  PERIOD_PATTERNS = [
    [/medieval/, :medieval],
    [/renaissance/, :renaissance],
    [/baroque/, :baroque],
    [/classical/, :classical],
    [/romantic/, :romantic],
    [/impressionist/, :impressionist],
    [/modern|contemporary|20th|21st/, :modern]
  ].freeze

  def navigation_svg_icon(category, size: 14, html_class: nil)
    key = category.to_s.downcase.to_sym
    icon_name = NAVIGATION_ICONS[key] || "music"
    lucide_icon(icon_name, size: size, class: html_class)
  end

  def period_svg_icon(name, size: 18, html_class: nil)
    icon_name = resolve_period_icon(name)
    lucide_icon(icon_name, size: size, class: html_class)
  end

  private

  def resolve_period_icon(name)
    return PERIOD_ICONS[:classical] if name.blank?

    normalized = name.to_s.downcase
    key = find_pattern_match(normalized, PERIOD_PATTERNS) || :classical
    PERIOD_ICONS[key]
  end

  def find_pattern_match(text, patterns)
    patterns.find { |pattern, _| text.match?(pattern) }&.last
  end
end
