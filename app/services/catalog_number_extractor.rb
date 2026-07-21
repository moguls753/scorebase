require "uri"

# Reconstructs an IMSLP catalog number (e.g. "P.257") from external_url, anchored on the stored bare title.
module CatalogNumberExtractor
  CATALOG_PREFIX = /\A(Op|BWV|WoO|Hob|HWV|TWV|RV|WD|Anh|S|K|P|D|L)\b\.?/

  module_function

  def extract(title, external_url)
    return nil if title.to_s.strip.empty? || external_url.to_s.strip.empty?
    return nil unless external_url.include?("imslp.org") && external_url.include?("/wiki/")

    # MediaWiki underscores ARE spaces in page titles; normalize after decoding so
    # the space-form title anchor matches both stored encodings (www-form and literal "_").
    name = URI.decode_www_form_component(external_url.split("/wiki/").last).tr("_", " ")
    name = name.sub(/\s*\([^)]*\)\s*\z/, "").strip

    rest = name.delete_prefix(title.strip)
    return nil unless rest.start_with?(",")

    suffix = rest.sub(/\A,\s*/, "").strip
    return nil unless catalog_shaped?(suffix)

    suffix
  end

  def catalog_shaped?(value)
    str = value.to_s.strip
    return false if str.empty? || str.include?("\n")

    str.match?(/\d/) || str.match?(CATALOG_PREFIX)
  end
end
