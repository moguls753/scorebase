# Matches free scores to professional SMD editions of the same piece.
#
# Matching works on RAW title/composer/artist columns — never
# title_search_normalized (SMD's embeds an SEO suffix) or
# composer_search_normalized (name order flips per
# source). Title-only matching measured 81% wrong-composer links, so a match
# requires the composer surname too; single-word generic form titles are
# stoplisted because the same composer often wrote several pieces by that name.
class SmdMatchFinder
  MAX_MATCHES = 3

  # A title that names a form rather than a work: the same composer wrote several,
  # so title+surname is not identity. The German and Latin entries arrive with the
  # Stretta catalogue — "Messe/Palestrina" would otherwise collapse a shelf of
  # different masses into one match.
  GENERIC_FORM_TITLES = %w[
    minuet menuet prelude allegro gavotte romance march overture andante
    adagio waltz nocturne etude sonata sonatina rondo intermezzo fugue
    aria scherzo serenade chorale sinfonia allemande courante sarabande
    gigue air musette bagatelle toccata berceuse elegie andantino arietta
    barcarolle impromptu mazurka polonaise ballade fantasia pastorale canon
    concerto concertino divertimento partita capriccio nocturno
    messe motette kanon choral lied sonate konzert variationen fuge
    walzer marsch tanz menuett arie hymne psalm
    praludium praeludium ouverture ouvertuere stuck stueck
    missa kyrie gloria credo sanctus benedictus requiem magnificat
  ].to_set.merge([
    "te deum", "salve regina", "pater noster", "ave maria", "ave verum", "agnus dei"
  ]).freeze

  # Coarse instrument families shared by both sides of a match. The SMD side reads
  # the clean, 100%-populated main_instrument column; the free side derives its via
  # .free_family (voicing / is_instrumental / instruments).
  SMD_FAMILY = {
    "Piano" => :piano, "Easy Piano" => :piano, "Educational Piano" => :piano,
    "Piano & Keyboard" => :piano, "Organ" => :piano,
    "Choir" => :vocal, "Vocal" => :vocal,
    "Guitar" => :guitar, "Ukulele" => :guitar, "Folk Instrument" => :guitar,
    "Violin" => :strings, "Viola" => :strings, "Cello" => :strings,
    "Strings" => :strings, "Other Strings" => :strings,
    "Sax" => :winds, "Flute" => :winds, "Clarinet" => :winds, "Trumpet" => :winds,
    "Other Brass" => :winds, "Woodwind" => :winds,
    "Band" => :band, "Orchestra" => :orchestra,
    "Lead Sheet / Fake Book" => :song, "Percussion" => :percussion
  }.freeze

  # Rows: [id, title, composer, artist, price_usd, main_instrument] (main_instrument
  # optional), keyed by normalized title.
  # Entries keep only what matching needs — retaining the full title, composer and
  # artist strings costs ~120 MB on the 209k-row catalogue and OOM-killed the job.
  # Pass an existing index to accumulate across batches.
  def self.build_index(smd_rows, index = {})
    smd_rows.each do |id, title, composer, artist, price, main_instrument|
      key = normalize(title)
      next if key.empty?

      # -"str" interns: ~209k entries share far fewer distinct surnames, and a
      # Float is a fraction of a BigDecimal — both matter at this row count. The
      # family symbol is interned, so it costs no meaningful memory.
      (index[key] ||= []) << [ id, title.include?(" - "), price&.to_f,
                               -surname(composer), -surname(artist), smd_family(main_instrument) ]
    end
    index
  end

  # Ranked SMD ids (uncapped; callers apply MAX_MATCHES after suppression).
  # free_family (the free score's coarse instrument family) floats same-family
  # editions to the top so a piano score surfaces a piano edition, not a banjo tab.
  def self.matches_for(title, composer, index, free_family: nil)
    key = normalize(title)
    return [] if key.empty? || GENERIC_FORM_TITLES.include?(key)

    wanted = surname(composer)
    return [] if wanted.empty?

    candidates = (index[key] || []).select do |_, _, _, composer_surname, artist_surname, _family|
      composer_surname == wanted || artist_surname == wanted
    end
    rank(candidates, free_family).map(&:first)
  end

  def self.normalize(text) = MusicText.normalize(text)
  def self.surname(name) = MusicText.surname(name)

  # Instrument-family match first (a piano score's piano edition beats its banjo
  # tab), then set listing first, price DESC (nil last), id for determinism. A
  # nil/unclassifiable free_family leaves every candidate equal, preserving the
  # price order. GROUP_REPRESENTATIVE_ORDER_SQL now leads with group_rank, which
  # SMD never sets, so the two orders still agree on SMD rows.
  def self.rank(entries, free_family = nil)
    entries.sort_by do |id, instrument_part, price, _, _, family|
      [ compatible?(free_family, family) ? 0 : 1,
        ensemble_mismatch?(free_family, family) ? 1 : 0,
        instrument_part ? 1 : 0, price.nil? ? 1 : 0, -(price || 0), id ]
    end
  end

  def self.smd_family(main_instrument)
    return :other if main_instrument.blank?

    SMD_FAMILY.fetch(main_instrument, :other)
  end

  # Cascade: the music21 is_instrumental flag is authoritative when set (it beats a
  # stray voicing value on an instrumental piece like a piano rag); otherwise a
  # vocal score is flagged by voicing (CPDL choir codes), else we parse instruments.
  def self.free_family(voicing, is_instrumental, instruments)
    return instrument_family(instruments) if is_instrumental == true
    return :vocal if is_instrumental == false || voicing.present?

    instrument_family(instruments)
  end

  def self.instrument_family(instruments)
    return :other if instruments.blank?

    case instruments.downcase
    when /satb|ssa|ttbb|choir|choral|voice|vocal/ then :vocal
    when /piano|keyboard|organ|harpsichord/ then :piano
    when /guitar|ukulele|\blute\b|banjo|mandolin/ then :guitar
    when /violin|viola|cello|double bass|contrabass|harp/ then :strings
    when /orchestra/ then :orchestra
    # Before the winds branch, or every wind band classifies as :winds and a free
    # band piece can never match a band edition — SMD_FAMILY has had :band all along.
    when /concert band|wind band|marching band|brass band|blasorchester|\bband\b/ then :band
    when /flute|clarinet|sax|oboe|bassoon|trumpet|horn|trombone|tuba|recorder/ then :winds
    else :other
    end
  end

  # A boost, not a filter: an unclassifiable side (:other/nil) never boosts, so
  # those matches keep plain price order. Only an exact family match boosts — a
  # thin lead-sheet must not outrank a fuller Piano Solo of the same piece.
  def self.compatible?(free_family, candidate_family)
    return false if free_family.nil? || free_family == :other || candidate_family == :other

    free_family == candidate_family
  end

  # A large-ensemble edition (concert/marching band, orchestra) is a poor top pick
  # for a solo/keyboard/vocal free score, so it sinks below smaller editions in the
  # no-family-match fallback regardless of its (usually higher) price. A genuine
  # band/orchestra free score keeps it.
  ENSEMBLE_FAMILIES = %i[band orchestra].freeze

  def self.ensemble_mismatch?(free_family, candidate_family)
    ENSEMBLE_FAMILIES.include?(candidate_family) && ENSEMBLE_FAMILIES.exclude?(free_family)
  end
end
