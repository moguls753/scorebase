# frozen_string_literal: true

class CpdlImporter
  module VoicingTemplate
    Result = Data.define(:voicing, :num_parts)

    SOLO_MAP = {
      "S" => "SoloS", "Solo S" => "SoloS", "Solo Soprano" => "SoloS",
      "A" => "SoloA", "Solo A" => "SoloA", "Solo Alto"    => "SoloA",
      "T" => "SoloT", "Solo T" => "SoloT", "Solo Tenor"   => "SoloT",
      "B" => "SoloB", "Solo B" => "SoloB", "Solo Bass"    => "SoloB"
    }.freeze

    TEMPLATE_RE = /\{\{Voicing\s*\|(.+?)\}\}/m

    def self.parse(wikitext)
      return Result.new(voicing: nil, num_parts: nil) if wikitext.blank?

      match = wikitext.match(TEMPLATE_RE)
      return Result.new(voicing: nil, num_parts: nil) unless match

      segments = match[1].split("|").reject { |s| s.strip.start_with?("add=") }
      num_parts, raw = extract_parts_and_raw(segments)
      Result.new(voicing: canonicalize(raw), num_parts: num_parts)
    end

    def self.canonicalize(raw)
      return nil if raw.nil? || raw.to_s.strip.empty?
      first = raw.split(/[|,]/).first.to_s.strip
      return nil if first.empty?
      SOLO_MAP.fetch(first, first)
    end

    def self.extract_parts_and_raw(segments)
      head = segments.first&.strip
      if head&.match?(/\A\d+\z/)
        [head.to_i, segments[1..].find(&:present?)]
      else
        [nil, segments.find(&:present?)]
      end
    end
    private_class_method :extract_parts_and_raw
  end
end
