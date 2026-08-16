# frozen_string_literal: true

# Groups the editions and parts of one Stretta publication
# (docs/stretta-import-plan.md §6).
#
# The "stretta:" prefix is load-bearing: assign_representatives is not filtered by
# source, so a key colliding with an SMD one would fuse both catalogues into one
# group and hide the losing source everywhere. norm(instrument) is too: a real
# part set repeats one instrument and varies itemtype, an arrangement series
# repeats one itemtype and varies instrument — drop it and the two collapse together.
module Stretta
  class Grouping
    PREFIX = "stretta:"

    # First match wins, so the specific forms precede the generic ones — otherwise
    # "Klavierpartitur, Solostimme" ranks as a single part and "Notenbuch,
    # Playback-CD" as a CD.
    RANKS = [
      [/stimmensatz|partitur,\s*stimmen/i, 5],
      [/chorpartitur/i, 20],
      [/klavierauszug/i, 30],
      [/studienpartitur|taschenpartitur/i, 40],
      [/notenbuch|chorbuch|liederbuch|songbook|spielbuch|sammelband/i, 50],
      [/orchesterstimme|einzelstimme/i, 70],
      [/partitur/i, 10],
      [/noten|tabulaturheft|tabularturheft|einzelausgabe|heft|solo/i, 10],
      [/stimme/i, 60],
      [/\bcd\b|\bdvd\b|playback|audio|mp3/i, 90]
    ].freeze

    UNRANKED = 50

    class << self
      # nil when there is no title — a key of nothing but empty fields is a
      # collection bin, not a group ("stretta:Wertach||||" held 69 unrelated rows).
      def key(product)
        title = MusicText.normalize(product[:title])
        return nil if title.empty?

        [
          PREFIX + product[:vendor].to_s,
          author_key(product),
          title,
          MusicText.normalize(product[:subtitle]),
          MusicText.normalize(product[:instrument]),
          delivery(product[:product_type]),
          order_stem(product[:vendor], product[:order_no])
        ].join("|")
      end

      # A printed edition and its PDF are separately priced and separately bought,
      # so they are two products and must not collapse into one card.
      def delivery(product_type)
        product_type.to_s.start_with?("dl_") ? "download" : "print"
      end

      # The publication an order number belongs to, with the component suffix
      # stripped — Carus numbers one publication CV 40.033/00 score, /05 choral
      # score, /11 violin 1, so two rows with different stems are two publications
      # even when title, author and scoring all match.
      #
      # Opt-in per publisher, biased towards stripping too little: that only costs
      # splitting power, where stripping too much explodes a part set into single-
      # item cards. Schott and Hal Leonard number every component separately, so
      # there's no suffix to strip and they get nothing.
      #
      # An unrecognised number yields the empty stem, never the raw number — raw
      # would split every unrecognised number from every other one.
      def order_stem(vendor, order_no)
        return "" if order_no.blank?

        stem =
          case vendor
          when "Carus Verlag" then carus_stem(order_no)
          when "Editions Marc Reift" then order_no[/\A[A-Za-z]+\s*\d+/]
          when "Alfred Music" then alfred_stem(order_no)
          end

        stem.to_s.upcase.delete(" ")
      end

      def rank(itemtype)
        return UNRANKED if itemtype.blank?

        RANKS.find { |pattern, _| itemtype.match?(pattern) }&.last || UNRANKED
      end

      private

      # One publication is written both "CV 40.001/19" and "CARUS 40001-19", and
      # with or without the leading zero ("CV 09.001" is "CV9.001"). All three
      # variants have to reduce to one stem or the part set tears in half.
      def carus_stem(order_no)
        digits = order_no[/\A(?:CV|CARUS)\s*([\d.]+)/i, 1]
        digits && "CV#{digits.delete('.').sub(/\A0+/, '')}"
      end

      # Alfred's PO/PS product lines only; the rest of its catalogue is numbered
      # differently and was never validated, so it gets no stem.
      def alfred_stem(order_no)
        match = order_no.match(/\A(\d+)-(?:PO|PS)-(\d+)\z/)
        match && "#{match[1]}-#{match[2]}"
      end

      # 39.1% of authors carry no slug; the normalised name stands in for them, and
      # a product with no author at all falls back to its order number.
      def author_key(product)
        authors = Array(product[:authors])
        return MusicText.normalize(product[:order_no]) if authors.empty?

        authors.map { |author| author[:slug].presence || MusicText.normalize(author[:name]) }
               .reject(&:blank?).sort.uniq.join(",")
      end
    end
  end
end
