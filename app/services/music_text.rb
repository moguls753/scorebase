# frozen_string_literal: true

# Shared text normalisation for every key that has to survive a round trip
# between catalogues: match keys, work keys and group keys.
module MusicText
  # These letters have no NFKD decomposition to ASCII, so they survive an accent
  # strip intact: in a match key they became a space ("Größe" -> "gro e"), in the
  # search column they stayed, so "grosser gott" never found "Großer Gott".
  # 347 free titles, 5,470 Stretta titles.
  LIGATURES = {
    "ß" => "ss", "ẞ" => "SS",
    "æ" => "ae", "Æ" => "AE",
    "œ" => "oe", "Œ" => "OE",
    "ø" => "o",  "Ø" => "O",
    "ł" => "l",  "Ł" => "L"
  }.freeze
  LIGATURE_PATTERN = Regexp.union(LIGATURES.keys).freeze

  # Accent-stripped, case preserved — for the columns the FTS triggers index.
  def self.fold(text)
    return "" if text.blank?

    text.gsub(LIGATURE_PATTERN, LIGATURES).unicode_normalize(:nfkd).gsub(/\p{M}/, "")
  end

  def self.normalize(text)
    fold(text).downcase.gsub(/[^a-z0-9]+/, " ").strip
  end

  # "Bach, Johann Sebastian" and "Johann Sebastian Bach" both give "bach".
  def self.surname(name)
    return "" if name.blank?

    head, comma, = name.partition(",")
    normalize(comma.empty? ? head.split.last : head)
  end
end
