# frozen_string_literal: true

# What makes a score a paid catalogue row: which partner sells it, in which
# currency, and out of which column its price is read.
module Score::Commercial
  extend ActiveSupport::Concern

  Partner = Data.define(:source, :name, :currency, :price_column, :original_price_column)

  COMMERCIAL_PARTNERS = [
    Partner.new(source: "smd", name: "Sheet Music Direct", currency: "USD",
                price_column: :price_usd, original_price_column: :original_price_usd),
    Partner.new(source: "stretta", name: "Stretta Music", currency: "EUR",
                price_column: :price_eur, original_price_column: :original_price_eur)
  ].index_by(&:source).freeze

  COMMERCIAL_SOURCES = COMMERCIAL_PARTNERS.keys.freeze

  included do
    scope :commercial, -> { where(source: COMMERCIAL_SOURCES) }
    scope :free, -> { where.not(source: COMMERCIAL_SOURCES) }
  end

  class_methods do
    # A commercial row carrying a positive price in its partner's own currency.
    # COALESCE keeps the negation NULL-safe: priceless commercial rows belong in
    # "free", and `NOT (price > 0)` is NULL — not true — for a NULL price.
    def priced_condition
      COMMERCIAL_PARTNERS.values.map { |partner|
        price = Arel::Nodes::NamedFunction.new(
          "COALESCE", [ arel_table[partner.price_column], Arel::Nodes.build_quoted(0) ]
        )
        arel_table[:source].eq(partner.source).and(price.gt(0))
      }.reduce(:or)
    end
  end

  def commercial?
    COMMERCIAL_PARTNERS.key?(source)
  end

  def partner
    COMMERCIAL_PARTNERS[source]
  end

  def partner_name = partner&.name
  def price_currency = partner&.currency
  def display_price = partner && self[partner.price_column]
  def display_original_price = partner && self[partner.original_price_column]

  # Commercial score with a valid external_id (can link to purchase). SMD never
  # populates available_for_sale (always nil), so this only excludes an explicit
  # false — a delisted Stretta product — never a partner that doesn't track it.
  def purchasable?
    commercial? && external_id.present? && available_for_sale != false
  end
end
