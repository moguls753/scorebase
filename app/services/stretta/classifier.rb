# frozen_string_literal: true

# Decides whether a Stretta product belongs in the catalogue.
#
# Three gates, in the order the measurement established (docs/stretta-import-plan.md §1):
# sellable → is it sheet music → has a title. Cross-source duplicates are not
# decided here; that is a converge over both catalogues (§7).
#
# The allowlist is a materialised list of exact itemtype values, never a rule:
# "everything in the top 1000" would have admitted socks, mugs and music stands.
module Stretta
  class Classifier
    LISTS = JSON.parse(Rails.root.join("config/stretta_itemtypes.json").read).freeze
    ALLOW = LISTS.fetch("allow").to_set.freeze
    DENY = LISTS.fetch("deny").to_set.freeze
    UNCLEAR = LISTS.fetch("unclear").to_set.freeze

    # `Buch` with a scoring is sheet music (43,808 of 59,720 bare-`Buch` rows carry
    # one; `Buch (Gebunden)` never does). It is also the only rule that costs
    # precision, so the categories that are subjects rather than scorings are cut.
    BOOK_ITEMTYPE = "Buch"
    NON_SCORING_INSTRUMENTS = /libretto|solfege|theory|musikerziehung/i

    Result = Data.define(:accepted, :reason) do
      def accepted? = accepted
    end

    class << self
      def classify(product)
        return reject(:not_for_sale) unless product[:available_for_sale]
        return reject(:no_title) if product[:title].blank?

        sheet_music(product)
      end

      private

      def sheet_music(product)
        itemtype = product[:itemtype].to_s.strip

        return book_with_scoring(product) if itemtype == BOOK_ITEMTYPE
        return empty_itemtype(product) if itemtype.empty?
        return accept(:allowlist) if ALLOW.include?(itemtype)
        return reject(:denylist) if DENY.include?(itemtype)
        return reject(:unclear_itemtype) if UNCLEAR.include?(itemtype)

        reject(:unlisted_itemtype)
      end

      def book_with_scoring(product)
        instrument = product[:instrument].to_s
        return reject(:book_without_scoring) if instrument.blank?
        return reject(:non_scoring_subject) if instrument.match?(NON_SCORING_INSTRUMENTS)

        accept(:book_with_scoring)
      end

      # A blank itemtype is 7.7% of the catalogue and mostly not sheet music. A
      # scoring alone is not enough — a page count or a preview PDF has to corroborate.
      def empty_itemtype(product)
        return reject(:empty_itemtype) if product[:instrument].blank?
        return reject(:empty_itemtype_uncorroborated) unless Array(product[:pages]).any? || product[:preview_pdf]

        accept(:empty_itemtype_corroborated)
      end

      def accept(reason) = Result.new(accepted: true, reason: reason)
      def reject(reason) = Result.new(accepted: false, reason: reason)
    end
  end
end
