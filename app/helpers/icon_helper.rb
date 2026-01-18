# frozen_string_literal: true

# SVG icon helper for ScoreBase
# Icons loaded from config/icons.yml
# All icons are 20x20 viewBox, 1.5px stroke, no fill
module IconHelper
  ICONS = YAML.load_file(Rails.root.join("config/icons.yml")).deep_symbolize_keys.freeze

  # Pattern order matters: specific patterns before generic ones
  # These patterns are fallbacks when exact key lookup fails
  INSTRUMENT_PATTERNS = [
    # Woodwinds - specific before generic
    [/piccolo/, :piccolo],
    [/recorder|block.?flute/, :recorder],
    [/saxophone|sax\b/, :saxophone],
    [/clarinet/, :clarinet],
    [/english.?horn|cor.?anglais/, :english_horn],
    [/oboe/, :oboe],
    [/bassoon|contrabassoon/, :bassoon],
    [/flute/, :flute],

    # Brass - specific before generic (flugelhorn/euphonium before horn/tuba)
    [/flugelhorn|flugel\b/, :flugelhorn],
    [/euphonium|euph\b/, :euphonium],
    [/trumpet/, :trumpet],
    [/trombone/, :trombone],
    [/cornet/, :cornet],
    [/horn/, :horn],
    [/tuba/, :tuba],

    # Strings - bowed (specific before generic)
    [/viola/, :viola],
    [/cello|violoncello/, :cello],
    [/double.?bass|contrabass|string.?bass/, :double_bass],
    [/violin|fiddle/, :violin],

    # Strings - plucked
    [/ukulele|uke\b/, :ukulele],
    [/mandolin/, :mandolin],
    [/banjo/, :banjo],
    [/theorbo/, :theorbo],
    [/lute/, :lute],
    [/guitar/, :guitar],
    [/harp/, :harp],

    # Keyboards
    [/harpsichord|cembalo/, :harpsichord],
    [/synthesizer|synth\b/, :synthesizer],
    [/accordion|squeezebox/, :accordion],
    [/organ/, :organ],
    [/piano/, :piano],

    # Percussion - specific before generic
    [/timpani|kettledrum/, :timpani],
    [/glockenspiel|glock\b|orchestra.?bells/, :glockenspiel],
    [/vibraphone|vibes\b/, :vibraphone],
    [/xylophone|xylo\b/, :xylophone],
    [/marimba/, :marimba],
    [/drum/, :drums],

    # Voice
    [/choir|chorus|choral/, :choir],
    [/voice|soprano|alto|tenor|bass|baritone|mezzo|cappella/, :voice],

    # Catch-all for generic string references
    [/string/, :violin]
  ].freeze

  GENRE_PATTERNS = [
    [/sacred|religious|hymn|mass|motet/, :sacred],
    [/choral|choir/, :sacred],
    [/jazz/, :jazz],
    [/folk|traditional/, :folk],
    [/opera|aria/, :opera],
    [/march|military/, :march],
    [/dance|waltz|polka|tango/, :dance]
  ].freeze

  PERIOD_PATTERNS = [
    [/medieval/, :medieval],
    [/renaissance/, :renaissance],
    [/baroque/, :baroque],
    [/classical/, :classical],
    [/romantic/, :romantic],
    [/impressionist/, :impressionist],
    [/modern|contemporary|20th|21st/, :modern]
  ].freeze

  def instrument_svg_icon(name, size: 18, html_class: nil)
    key = resolve_instrument_key(name)
    svg_content = ICONS[:instruments][key] || ICONS[:instruments][:orchestra]
    build_svg(svg_content, size, html_class)
  end

  def genre_svg_icon(name, size: 18, html_class: nil)
    key = resolve_genre_key(name)
    svg_content = ICONS[:genres][key] || ICONS[:periods][key] || ICONS[:genres][:default]
    build_svg(svg_content, size, html_class)
  end

  def period_svg_icon(name, size: 18, html_class: nil)
    key = resolve_period_key(name)
    svg_content = ICONS[:periods][key] || ICONS[:periods][:classical]
    build_svg(svg_content, size, html_class)
  end

  private

  def resolve_instrument_key(name)
    return :orchestra if name.blank?

    normalized = name.to_s.downcase.gsub(/[^a-z]/, "_")
    return normalized.to_sym if ICONS[:instruments].key?(normalized.to_sym)

    find_pattern_match(normalized, INSTRUMENT_PATTERNS) || :orchestra
  end

  def resolve_genre_key(name)
    return :default if name.blank?

    normalized = name.to_s.downcase
    # Check periods first (classical, baroque, romantic share icons)
    return normalized.to_sym if ICONS[:periods].key?(normalized.to_sym)

    find_pattern_match(normalized, GENRE_PATTERNS) || :default
  end

  def resolve_period_key(name)
    return :classical if name.blank?

    normalized = name.to_s.downcase
    find_pattern_match(normalized, PERIOD_PATTERNS) || :classical
  end

  def find_pattern_match(text, patterns)
    patterns.find { |pattern, _| text.match?(pattern) }&.last
  end

  def build_svg(content, size, html_class)
    class_attr = html_class ? %( class="#{html_class}") : ""
    %(<svg xmlns="http://www.w3.org/2000/svg" width="#{size}" height="#{size}" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"#{class_attr} aria-hidden="true">#{content}</svg>).html_safe
  end
end
