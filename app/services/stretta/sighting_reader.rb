# frozen_string_literal: true

require "sqlite3"

# Reads the local full sighting in the same shape Stretta::Product builds from the
# API, so the offline selection and the live import classify identically.
module Stretta
  class SightingReader
    DEFAULT_PATH = "storage/stretta-sighting.sqlite3"

    # One literal query, and the vendor filter applied in Ruby. A dynamic IN-list
    # would be a built SQL string, which Brakeman cannot tell from an injection —
    # and this reads the whole 1.7M-row table in ~18s either way.
    QUERY = <<~SQL.squish.freeze
      SELECT handle, available_for_sale, text_title, itemtype, instrument,
             pages, has_preview_pdf, vendor
      FROM products
    SQL

    def initialize(path: DEFAULT_PATH)
      @path = Rails.root.join(path)
    end

    def count
      connection.get_first_value("SELECT count(*) FROM products")
    end

    # Yields [handle, product]. Restricted to `vendors` when given.
    def each_product(vendors: [])
      return enum_for(:each_product, vendors: vendors) unless block_given?

      wanted = vendors.to_set
      connection.execute(QUERY) do |row|
        next if wanted.any? && wanted.exclude?(row["vendor"])

        yield row["handle"], product_from(row)
      end
    end

    private

    def connection
      @connection ||= SQLite3::Database.new("file:#{@path}?mode=ro", results_as_hash: true)
    end

    def product_from(row)
      {
        available_for_sale: row["available_for_sale"] == 1,
        title: row["text_title"],
        itemtype: row["itemtype"],
        instrument: row["instrument"],
        pages: parse_pages(row["pages"]),
        preview_pdf: row["has_preview_pdf"] == 1
      }
    end

    def parse_pages(raw)
      JSON.parse(raw.presence || "[]")
    rescue JSON::ParserError
      []
    end
  end
end
