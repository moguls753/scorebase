# frozen_string_literal: true

# Turns one Stretta product into a Score row (docs/stretta-import-plan.md §3–§5).
#
# Everything a callback would normally derive is set here: the import writes with
# upsert_all, which runs no callbacks. Missing title_search_normalized alone would
# leave the whole catalogue unfindable behind a database that looks healthy.
module Stretta
  class ProductMapper
    GRADE_LABELS = {
      1 => { en: "beginner",     de: "sehr leicht" },
      2 => { en: "elementary",   de: "leicht" },
      3 => { en: "intermediate", de: "mittelschwer" },
      4 => { en: "advanced",     de: "anspruchsvoll" },
      5 => { en: "expert",       de: "sehr anspruchsvoll" }
    }.freeze

    # A span wider than two steps says nothing: "1-5" as "beginner" is a guess.
    MAX_GRADE_SPAN = 1

    METADATA_KEYS = %i[
      raw_title subtitle itemtype instrument order_no ismn isbn pages
      difficulty minquantity bulk_prices vendor slugs facets product_type authors classification_reason
    ].freeze

    def initialize(composer_index: nil, now: Time.current)
      @composer_index = composer_index
      @now = now
    end

    # nil when the product cannot become a Score at all.
    def call(product, classification_reason: nil)
      title = product[:title].to_s.strip
      return nil if title.blank?

      base(product, title)
        .merge(composer_attributes(product))
        .merge(instrument_attributes(product[:instrument]))
        .merge(grade_attributes(product[:difficulty]))
        .merge(metadata_attributes(product, classification_reason))
    end

    private

    def base(product, title)
      {
        source: "stretta",
        external_id: product[:handle].to_s,
        title: title,
        title_search_normalized: Score.normalize_for_search(title),
        brand: product[:vendor],
        partner_slug: product[:slug_de],
        price_eur: product[:price],
        original_price_eur: product[:compare_at_price],
        available_for_sale: product[:available_for_sale],
        page_count: page_count(product[:pages]),
        smd_category: Instruments.hub_category(product[:instrument]),
        thumbnail_url: product[:image_url],
        work_key: work_key(product),
        group_key: Grouping.key(product),
        group_rank: Grouping.rank(product[:itemtype]),
        last_crawled_at: @now,
        extraction_status: "no_musicxml",
        genre_status: "not_applicable",
        period_status: "not_applicable",
        rag_status: "not_applicable"
      }
    end

    # The work key uses the bare work title, never the display title, or nothing
    # would ever line up with an SMD row.
    def work_key(product)
      title = MusicText.normalize(product[:title])
      return nil if title.empty?

      surname = MusicText.surname(composer_name(product))
      return nil if surname.empty?

      "#{title}|#{surname}"
    end

    # role == "author" is the composer; authors[0] is the arranger on arrangements.
    def composer_name(product)
      Array(product[:authors]).find { |author| author[:role] == "author" }&.dig(:name).presence
    end

    # No reversal rule of our own: Stretta carries both orders without a comma
    # ("Georges Brassens" and "Brassens Georges"), so "last token first" invents
    # "Georges, Brassens". ComposerMapping already knows the German forms.
    def composer_attributes(product)
      name = composer_name(product)
      return { composer: nil, composer_search_normalized: nil, composer_status: "not_applicable" } if name.blank?
      if ComposerMapping.known_unnormalizable?(name)
        return { composer: name, composer_search_normalized: Score.normalize_for_search(name),
                 composer_status: "not_applicable" }
      end

      canonical = lookup(name)
      {
        composer: canonical || name,
        composer_search_normalized: Score.normalize_for_search(canonical || name),
        composer_status: canonical ? "normalized" : "pending"
      }
    end

    def lookup(name)
      @composer_index ? @composer_index[name] : ComposerMapping.lookup(name)
    end

    # instruments_status follows the VALID_INSTRUMENTS hit, not the column: a row
    # whose scoring only resolved to an ensemble shows "Wind Band" but stays
    # pending, because calling an unhubbable value "normalized" bars it forever.
    def instrument_attributes(scoring)
      instruments = Instruments.parse(scoring)
      voicing = Instruments.voicing(scoring)

      {
        instruments: instruments,
        instruments_status: Instruments.normalized?(scoring) ? "normalized" : "pending",
        voicing: voicing,
        voicing_status: voicing.present? ? "normalized" : "not_applicable",
        has_vocal: voicing.present? || instruments.to_s.include?("Voice"),
        has_vocal_status: "normalized"
      }
    end

    # Ranges occur ("2-3", 20,353 rows); to_i takes the lower bound, which is the
    # wanted reading, where Integer() would raise.
    #
    # Every branch returns the same keys — upsert_all rejects a batch whose rows
    # differ in shape, and the difference would only surface mid-import.
    def grade_attributes(difficulty)
      labels = GRADE_LABELS[grade_level(difficulty)]
      return { pedagogical_grade: nil, pedagogical_grade_de: nil, grade_source: nil,
               grade_status: "not_applicable" } unless labels

      {
        pedagogical_grade: Score::DIFFICULTY_LEVELS.fetch(labels[:en]).first,
        pedagogical_grade_de: labels[:de],
        grade_source: "stretta",
        grade_status: "normalized"
      }
    end

    def grade_level(difficulty)
      value = difficulty.to_s.strip
      return nil if value.empty?

      low, high = value.split("-").map(&:to_i)
      return nil unless GRADE_LABELS.key?(low)
      return nil if high && high - low > MAX_GRADE_SPAN

      low
    end

    def page_count(pages)
      Array(pages).first.to_s[/\d+/]&.to_i
    end

    def metadata_attributes(product, classification_reason)
      metadata = {
        raw_title: product[:title],
        subtitle: product[:subtitle],
        itemtype: product[:itemtype],
        instrument: product[:instrument],
        order_no: product[:order_no],
        ismn: product[:ismn],
        isbn: product[:isbn],
        pages: product[:pages],
        difficulty: product[:difficulty],
        minquantity: product[:minquantity],
        bulk_prices: product[:bulk_prices],
        vendor: product[:vendor],
        product_type: product[:product_type],
        authors: product[:authors],
        slugs: product[:slugs],
        facets: product[:facets],
        classification_reason: classification_reason
      }.slice(*METADATA_KEYS).compact_blank

      { stretta_metadata: metadata }
    end
  end
end
