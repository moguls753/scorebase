# frozen_string_literal: true

# SVG icon helper for ScoreBase
# Bold, simple icons matching the neubrutalism aesthetic
# All icons are 20x20 viewBox, 2px stroke, no fill
module IconHelper
  ICON_DEFAULTS = {
    size: 20,
    stroke_width: 2,
    class: ""
  }.freeze

  # Instrument icons - simple, recognizable silhouettes
  INSTRUMENT_SVGS = {
    # Keyboard instruments
    piano: <<~SVG,
      <path d="M2 5h16v10H2z"/>
      <path d="M5 5v6M8 5v6M11 5v6M14 5v6"/>
      <path d="M4 5v4h2V5M7 5v4h2V5M12 5v4h2V5M15 5v4h2V5"/>
    SVG
    organ: <<~SVG,
      <path d="M3 16V6l7-3 7 3v10"/>
      <path d="M6 16V8M10 16V5M14 16V8"/>
      <circle cx="10" cy="13" r="1.5"/>
    SVG
    harpsichord: <<~SVG,
      <path d="M2 8h12l4 4v3H2z"/>
      <path d="M5 8v7M8 8v7M11 8v7"/>
    SVG

    # Bowed strings
    violin: <<~SVG,
      <ellipse cx="10" cy="13" rx="5" ry="4"/>
      <path d="M10 9V2"/>
      <path d="M7 5h6"/>
      <circle cx="8" cy="13" r="1"/><circle cx="12" cy="13" r="1"/>
    SVG
    viola: <<~SVG,
      <ellipse cx="10" cy="12" rx="5.5" ry="4.5"/>
      <path d="M10 7.5V2"/>
      <path d="M7 4.5h6"/>
      <circle cx="8" cy="12" r="1"/><circle cx="12" cy="12" r="1"/>
    SVG
    cello: <<~SVG,
      <ellipse cx="10" cy="12" rx="6" ry="5"/>
      <path d="M10 7V2"/>
      <path d="M6 4h8"/>
      <path d="M10 17v1"/>
      <circle cx="8" cy="12" r="1"/><circle cx="12" cy="12" r="1"/>
    SVG
    double_bass: <<~SVG,
      <ellipse cx="10" cy="12" rx="6" ry="5"/>
      <path d="M10 7V1"/>
      <path d="M6 3h8"/>
      <path d="M10 17v2"/>
      <circle cx="8" cy="12" r="1"/><circle cx="12" cy="12" r="1"/>
    SVG

    # Plucked strings
    guitar: <<~SVG,
      <ellipse cx="10" cy="13" rx="6" ry="5"/>
      <circle cx="10" cy="13" r="2"/>
      <path d="M10 8V2"/>
      <path d="M7 3h6"/>
    SVG
    harp: <<~SVG,
      <path d="M5 18V4c0-1 1-2 2-2h2c4 0 7 3 7 7v9"/>
      <path d="M5 6h9M5 9h10M5 12h10M5 15h9"/>
    SVG
    lute: <<~SVG,
      <ellipse cx="10" cy="13" rx="6" ry="5"/>
      <path d="M10 8V2l3-1"/>
      <circle cx="10" cy="13" r="1.5"/>
    SVG
    mandolin: <<~SVG,
      <ellipse cx="10" cy="14" rx="5" ry="4"/>
      <path d="M10 10V2"/>
      <path d="M7 3h6"/>
      <circle cx="10" cy="14" r="1.5"/>
    SVG
    banjo: <<~SVG,
      <circle cx="10" cy="13" r="5"/>
      <path d="M10 8V2"/>
      <path d="M8 3h4"/>
    SVG
    ukulele: <<~SVG,
      <ellipse cx="10" cy="14" rx="4" ry="3.5"/>
      <path d="M10 10.5V3"/>
      <path d="M8 4h4"/>
      <circle cx="10" cy="14" r="1"/>
    SVG
    theorbo: <<~SVG,
      <ellipse cx="10" cy="14" rx="5" ry="4"/>
      <path d="M10 10V1"/>
      <path d="M6 2h3M11 3h3"/>
    SVG

    # Woodwinds
    flute: <<~SVG,
      <path d="M2 10h16"/>
      <circle cx="5" cy="10" r="1.5"/>
      <circle cx="9" cy="10" r="1"/>
      <circle cx="12" cy="10" r="1"/>
      <circle cx="15" cy="10" r="1"/>
    SVG
    piccolo: <<~SVG,
      <path d="M4 10h12"/>
      <circle cx="7" cy="10" r="1"/>
      <circle cx="10" cy="10" r="1"/>
      <circle cx="13" cy="10" r="1"/>
    SVG
    recorder: <<~SVG,
      <path d="M10 2v16"/>
      <circle cx="10" cy="6" r="1"/>
      <circle cx="10" cy="9" r="1"/>
      <circle cx="10" cy="12" r="1"/>
      <path d="M8 16l2 2 2-2"/>
    SVG
    clarinet: <<~SVG,
      <path d="M10 2v14"/>
      <rect x="8" y="2" width="4" height="3"/>
      <circle cx="10" cy="8" r="1"/>
      <circle cx="10" cy="11" r="1"/>
      <ellipse cx="10" cy="17" rx="2" ry="1.5"/>
    SVG
    oboe: <<~SVG,
      <path d="M10 3v13"/>
      <path d="M9 2h2v2H9z"/>
      <circle cx="10" cy="7" r="1"/>
      <circle cx="10" cy="10" r="1"/>
      <ellipse cx="10" cy="17" rx="2.5" ry="1.5"/>
    SVG
    bassoon: <<~SVG,
      <path d="M7 3v14M13 5v12"/>
      <path d="M7 17c0 1 2.5 1.5 6 0"/>
      <path d="M5 3h4"/>
      <circle cx="7" cy="8" r="1"/>
      <circle cx="13" cy="10" r="1"/>
    SVG
    english_horn: <<~SVG,
      <path d="M10 3v13"/>
      <path d="M8 2h4"/>
      <circle cx="10" cy="7" r="1"/>
      <circle cx="10" cy="10" r="1"/>
      <ellipse cx="10" cy="17.5" rx="3" ry="1.5"/>
    SVG
    saxophone: <<~SVG,
      <path d="M7 2c0 2 2 3 2 6s-3 6-3 9c0 1 1 2 3 2"/>
      <circle cx="6" cy="17" r="2"/>
      <path d="M6 2h3"/>
    SVG

    # Brass
    trumpet: <<~SVG,
      <path d="M2 10h12"/>
      <path d="M14 7v6l4 2v-10z"/>
      <circle cx="5" cy="10" r="1.5"/>
      <circle cx="8" cy="10" r="1.5"/>
      <circle cx="11" cy="10" r="1.5"/>
    SVG
    trombone: <<~SVG,
      <path d="M2 8h8v4H2z"/>
      <path d="M10 6h4v8h-4"/>
      <path d="M14 8v4l4 1v-6z"/>
    SVG
    horn: <<~SVG,
      <circle cx="10" cy="10" r="6" fill="none"/>
      <path d="M16 10h2"/>
      <circle cx="10" cy="10" r="2"/>
    SVG
    tuba: <<~SVG,
      <ellipse cx="10" cy="13" rx="6" ry="5"/>
      <path d="M10 8V3"/>
      <path d="M7 4h6"/>
      <ellipse cx="10" cy="13" rx="2" ry="1.5"/>
    SVG
    cornet: <<~SVG,
      <path d="M2 10h10"/>
      <path d="M12 7v6l5 2V5z"/>
      <circle cx="5" cy="10" r="1.5"/>
      <circle cx="8" cy="10" r="1.5"/>
    SVG
    flugelhorn: <<~SVG,
      <path d="M2 10h9"/>
      <path d="M11 6v8l6 2V4z"/>
      <circle cx="5" cy="10" r="1.5"/>
      <circle cx="8" cy="10" r="1.5"/>
    SVG
    euphonium: <<~SVG,
      <ellipse cx="10" cy="12" rx="5" ry="4"/>
      <path d="M10 8V4"/>
      <path d="M7 5h6"/>
      <circle cx="10" cy="12" r="1.5"/>
    SVG

    # Percussion
    timpani: <<~SVG,
      <ellipse cx="10" cy="8" rx="7" ry="3"/>
      <path d="M3 8v6c0 2 3 3 7 3s7-1 7-3V8"/>
    SVG
    drums: <<~SVG,
      <ellipse cx="10" cy="6" rx="6" ry="2"/>
      <path d="M4 6v8c0 1.5 2.5 3 6 3s6-1.5 6-3V6"/>
      <path d="M2 4l5 5M18 4l-5 5"/>
    SVG
    percussion: <<~SVG,
      <circle cx="6" cy="10" r="4"/>
      <circle cx="14" cy="10" r="4"/>
      <path d="M2 4l4 4M18 4l-4 4"/>
    SVG
    xylophone: <<~SVG,
      <rect x="2" y="7" width="3" height="10" rx="0.5"/>
      <rect x="6" y="5" width="3" height="12" rx="0.5"/>
      <rect x="10" y="4" width="3" height="13" rx="0.5"/>
      <rect x="14" y="6" width="3" height="11" rx="0.5"/>
    SVG
    marimba: <<~SVG,
      <rect x="2" y="6" width="3" height="11" rx="0.5"/>
      <rect x="6" y="4" width="3" height="13" rx="0.5"/>
      <rect x="10" y="3" width="3" height="14" rx="0.5"/>
      <rect x="14" y="5" width="3" height="12" rx="0.5"/>
    SVG
    vibraphone: <<~SVG,
      <rect x="3" y="5" width="2.5" height="8" rx="0.5"/>
      <rect x="7" y="4" width="2.5" height="9" rx="0.5"/>
      <rect x="11" y="4" width="2.5" height="9" rx="0.5"/>
      <rect x="15" y="5" width="2.5" height="8" rx="0.5"/>
      <path d="M4 14v3M8 14v3M12 14v3M16 14v3"/>
    SVG
    glockenspiel: <<~SVG,
      <rect x="3" y="7" width="2" height="6" rx="0.5"/>
      <rect x="6" y="6" width="2" height="7" rx="0.5"/>
      <rect x="9" y="5" width="2" height="8" rx="0.5"/>
      <rect x="12" y="6" width="2" height="7" rx="0.5"/>
      <rect x="15" y="7" width="2" height="6" rx="0.5"/>
    SVG

    # Voice
    voice: <<~SVG,
      <circle cx="10" cy="6" r="4"/>
      <path d="M6 10c0 4 2 7 4 8 2-1 4-4 4-8"/>
    SVG
    choir: <<~SVG,
      <circle cx="6" cy="5" r="2.5"/>
      <circle cx="14" cy="5" r="2.5"/>
      <circle cx="10" cy="8" r="2.5"/>
      <path d="M4 8v5M8 11v4M12 11v4M16 8v5"/>
    SVG

    # Other
    keyboard: <<~SVG,
      <path d="M2 6h16v8H2z"/>
      <path d="M5 6v5M8 6v5M11 6v5M14 6v5"/>
    SVG
    accordion: <<~SVG,
      <rect x="2" y="4" width="5" height="12" rx="1"/>
      <rect x="13" y="4" width="5" height="12" rx="1"/>
      <path d="M7 6h6M7 10h6M7 14h6"/>
    SVG
    synthesizer: <<~SVG,
      <rect x="2" y="7" width="16" height="8" rx="1"/>
      <path d="M4 10h2M7 10h2M10 10h2M13 10h2"/>
      <circle cx="5" cy="13" r="0.5"/><circle cx="8" cy="13" r="0.5"/>
      <circle cx="11" cy="13" r="0.5"/><circle cx="14" cy="13" r="0.5"/>
    SVG
    orchestra: <<~SVG,
      <path d="M10 2v4"/>
      <path d="M6 8l4-2 4 2"/>
      <path d="M4 12c2-2 4-2 6-2s4 0 6 2"/>
      <path d="M2 17c3-3 6-3 8-3s5 0 8 3"/>
    SVG
    continuo: <<~SVG,
      <path d="M2 5h16v10H2z"/>
      <path d="M5 5v6M8 5v6M11 5v6M14 5v6"/>
    SVG
  }.freeze

  # Period icons - era-appropriate symbols
  PERIOD_SVGS = {
    medieval: <<~SVG,
      <path d="M10 2v3M6 5h8l-1 3H7l-1-3z"/>
      <path d="M6 8v8l4 2 4-2V8"/>
      <path d="M8 11h4M8 14h4"/>
    SVG
    renaissance: <<~SVG,
      <circle cx="10" cy="8" r="5"/>
      <path d="M10 13v5"/>
      <path d="M7 15h6"/>
      <path d="M8 6c1-1 3-1 4 0"/>
    SVG
    baroque: <<~SVG,
      <path d="M7 18V4c0-1 .5-2 2-2s2 1 2 2"/>
      <ellipse cx="5" cy="16" rx="3" ry="2"/>
      <path d="M11 5c3 0 5 2 5 5s-2 4-4 4"/>
      <path d="M12 10c1 0 2 .5 2 1.5"/>
    SVG
    classical: <<~SVG,
      <path d="M8 18V4c0-1 .5-2 2-2s2 1 2 2"/>
      <ellipse cx="6" cy="16" rx="4" ry="2.5"/>
    SVG
    romantic: <<~SVG,
      <path d="M10 18V6"/>
      <path d="M10 6c0-2 2-4 5-4 0 3-2 5-5 5"/>
      <ellipse cx="7" cy="16" rx="4" ry="2.5"/>
      <path d="M14 10c1.5 0 3 1 3 2.5s-1.5 2.5-3 2.5"/>
    SVG
    impressionist: <<~SVG,
      <path d="M3 12c2-2 4-2 7-2s5 0 7 2"/>
      <path d="M4 8c1.5-1.5 3-1.5 6-1.5s4.5 0 6 1.5"/>
      <path d="M5 16c1.5 1 3 1 5 1s3.5 0 5-1"/>
      <circle cx="10" cy="12" r="2"/>
    SVG
    modern: <<~SVG,
      <rect x="4" y="4" width="5" height="12"/>
      <rect x="11" y="6" width="5" height="10"/>
      <path d="M6 8h2M6 12h2"/>
      <path d="M13 9h2M13 13h2"/>
    SVG
  }.freeze

  # Genre icons - thematic symbols
  GENRE_SVGS = {
    classical: <<~SVG,
      <path d="M8 18V4c0-1 .5-2 2-2s2 1 2 2"/>
      <ellipse cx="6" cy="16" rx="4" ry="2.5"/>
    SVG
    baroque: <<~SVG,
      <path d="M8 18V4c0-1 .5-2 2-2s2 1 2 2"/>
      <ellipse cx="6" cy="16" rx="4" ry="2.5"/>
      <path d="M12 6c2 0 3 1 3 3"/>
    SVG
    romantic: <<~SVG,
      <path d="M10 18V6"/>
      <path d="M10 6c0-2 2-4 5-4 0 3-2 5-5 5"/>
      <ellipse cx="7" cy="16" rx="4" ry="2.5"/>
    SVG
    sacred: <<~SVG,
      <path d="M10 2v16M6 6h8"/>
      <path d="M4 18h12"/>
    SVG
    choral: <<~SVG,
      <path d="M10 2v16M6 6h8"/>
      <path d="M4 18h12"/>
    SVG
    jazz: <<~SVG,
      <path d="M7 2c0 2 2 3 2 6s-3 6-3 9c0 1 1 2 3 2"/>
      <circle cx="6" cy="17" r="2"/>
      <path d="M6 2h3"/>
    SVG
    folk: <<~SVG,
      <ellipse cx="10" cy="13" rx="6" ry="5"/>
      <circle cx="10" cy="13" r="2"/>
      <path d="M10 8V2"/>
      <path d="M7 3h6"/>
    SVG
    opera: <<~SVG,
      <circle cx="7" cy="8" r="4"/>
      <circle cx="13" cy="8" r="4"/>
      <path d="M5 12c1 3 3 5 5 5s4-2 5-5"/>
    SVG
    march: <<~SVG,
      <rect x="4" y="6" width="12" height="10" rx="1"/>
      <path d="M7 6V4M13 6V4"/>
      <path d="M7 11h6"/>
    SVG
    dance: <<~SVG,
      <circle cx="10" cy="5" r="3"/>
      <path d="M10 8v4"/>
      <path d="M6 18l4-6 4 6"/>
      <path d="M6 12h8"/>
    SVG
    default: <<~SVG,
      <circle cx="10" cy="12" r="3"/>
      <path d="M10 9V3"/>
      <path d="M10 3l3 2"/>
    SVG
  }.freeze

  # Main method to render an instrument icon
  def instrument_svg_icon(name, size: 18, css_class: "")
    key = normalize_instrument_key(name)
    svg_content = INSTRUMENT_SVGS[key] || INSTRUMENT_SVGS[:orchestra]
    build_svg(svg_content, size: size, css_class: "instrument-icon #{css_class}".strip)
  end

  # Main method to render a genre icon
  def genre_svg_icon(name, size: 18, css_class: "")
    key = normalize_genre_key(name)
    svg_content = GENRE_SVGS[key] || GENRE_SVGS[:default]
    build_svg(svg_content, size: size, css_class: "genre-icon #{css_class}".strip)
  end

  # Main method to render a period icon
  def period_svg_icon(name, size: 18, css_class: "")
    key = normalize_period_key(name)
    svg_content = PERIOD_SVGS[key] || PERIOD_SVGS[:classical]
    build_svg(svg_content, size: size, css_class: "period-icon #{css_class}".strip)
  end

  private

  def normalize_instrument_key(name)
    return :orchestra if name.blank?

    downcased = name.to_s.downcase.gsub(/[^a-z]/, "_")

    # Direct matches first
    INSTRUMENT_SVGS.each_key do |key|
      return key if downcased.include?(key.to_s)
    end

    # Pattern matching for categories
    case downcased
    when /viola/ then :viola
    when /cello/ then :cello
    when /bass/ then :double_bass
    when /violin|fiddle|string/ then :violin
    when /flute/ then :flute
    when /clarinet/ then :clarinet
    when /oboe/ then :oboe
    when /bassoon|contrabassoon/ then :bassoon
    when /trumpet/ then :trumpet
    when /trombone/ then :trombone
    when /horn/ then :horn
    when /tuba/ then :tuba
    when /drum|percussion/ then :drums
    when /voice|choir|soprano|alto|tenor|baritone|mezzo|cappella/ then :voice
    when /guitar/ then :guitar
    when /piano|keyboard/ then :piano
    when /organ/ then :organ
    when /harp/ then :harp
    when /saxophone|sax/ then :saxophone
    else :orchestra
    end
  end

  def normalize_genre_key(name)
    return :default if name.blank?

    downcased = name.to_s.downcase

    case downcased
    when /classical/ then :classical
    when /baroque/ then :baroque
    when /romantic/ then :romantic
    when /sacred|religious|hymn|mass|motet/ then :sacred
    when /choral|choir/ then :choral
    when /jazz/ then :jazz
    when /folk|traditional/ then :folk
    when /opera|aria/ then :opera
    when /march|military/ then :march
    when /dance|waltz|polka|tango/ then :dance
    else :default
    end
  end

  def normalize_period_key(name)
    return :classical if name.blank?

    downcased = name.to_s.downcase

    case downcased
    when /medieval/ then :medieval
    when /renaissance/ then :renaissance
    when /baroque/ then :baroque
    when /classical/ then :classical
    when /romantic/ then :romantic
    when /impressionist/ then :impressionist
    when /modern|contemporary|20th|21st/ then :modern
    else :classical
    end
  end

  def build_svg(content, size:, css_class:)
    <<~SVG.html_safe
      <svg
        xmlns="http://www.w3.org/2000/svg"
        width="#{size}"
        height="#{size}"
        viewBox="0 0 20 20"
        fill="none"
        stroke="currentColor"
        stroke-width="1.5"
        stroke-linecap="round"
        stroke-linejoin="round"
        class="#{css_class}"
        aria-hidden="true"
      >#{content}</svg>
    SVG
  end
end
