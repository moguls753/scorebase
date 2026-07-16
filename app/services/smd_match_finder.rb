# Matches free scores to professional SMD editions of the same piece.
#
# Matching works on RAW title/composer/artist columns — never title_normalized
# (SMD's embeds an SEO suffix) or composer_normalized (name order flips per
# source). Title-only matching measured 81% wrong-composer links, so a match
# requires the composer surname too; single-word generic form titles are
# stoplisted because the same composer often wrote several pieces by that name.
class SmdMatchFinder
  MAX_MATCHES = 3

  GENERIC_FORM_TITLES = %w[
    minuet menuet prelude allegro gavotte romance march overture andante
    adagio waltz nocturne etude sonata sonatina rondo intermezzo fugue
    aria scherzo serenade chorale sinfonia allemande courante sarabande
    gigue air musette bagatelle toccata berceuse elegie andantino arietta
    barcarolle impromptu mazurka polonaise ballade fantasia pastorale canon
  ].to_set.freeze

  # Rows: [id, title, composer, artist, price_usd], keyed by normalized title
  def self.build_index(smd_rows)
    smd_rows.group_by { |row| normalize(row[1]) }.tap { |index| index.delete("") }
  end

  # Ranked SMD ids (uncapped; callers apply MAX_MATCHES after suppression)
  def self.matches_for(title, composer, index)
    key = normalize(title)
    return [] if key.empty? || GENERIC_FORM_TITLES.include?(key)

    wanted = surname(composer)
    return [] if wanted.empty?

    candidates = (index[key] || []).select do |row|
      surname(row[2]) == wanted || surname(row[3]) == wanted
    end
    rank(candidates).map(&:first)
  end

  def self.normalize(text)
    return "" if text.blank?
    text.unicode_normalize(:nfkd).gsub(/\p{M}/, "")
        .downcase.gsub(/[^a-z0-9]+/, " ").strip
  end

  def self.surname(name)
    return "" if name.blank?
    head, comma, = name.partition(",")
    normalize(comma.empty? ? head.split.last : head)
  end

  # Same value-rank as GROUP_REPRESENTATIVE_ORDER_SQL: set listing first,
  # then price DESC (nil last), then id for determinism
  def self.rank(rows)
    rows.sort_by do |id, title, _, _, price|
      [ title.include?(" - ") ? 1 : 0, price.nil? ? 1 : 0, -(price || 0), id ]
    end
  end
end
