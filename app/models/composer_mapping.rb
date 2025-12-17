# frozen_string_literal: true

# == Schema Information
#
# Table name: composer_mappings
#
#  id              :integer          not null, primary key
#  normalized_name :string
#  original_name   :string           not null
#  source          :string
#  verified        :boolean          default(FALSE), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_composer_mappings_on_normalized_name  (normalized_name)
#  index_composer_mappings_on_original_name    (original_name) UNIQUE
#
class ComposerMapping < ApplicationRecord
  validates :original_name, presence: true, uniqueness: true

  # Patterns that can NEVER be normalized to a real composer.
  # These get cached with nil to avoid re-processing.
  # Be conservative: "Dowland, Unknown" has a real composer, don't match it.
  UNNORMALIZABLE_PATTERNS = [
    /an[oóô]n/i,                              # anonymous, anonymus, anónimo, anônimo
    /\A\s*\(?unknown\)?\s*\.?\s*\z/i,         # "unknown", "(unknown)", "Unknown." alone
    /\bunknown\s+(composer|artist|piece)/i,   # "unknown composer", "unknown artist"
    /\b(composer|music)[:\s-]+unknown\b/i,    # "composer: unknown", "music - unknown"
    /\burheber\s*unbekannt/i,                  # German: "author unknown"
    /\btraditional\b/i,
    /\bfolk\b/i,
    /\bvarious\b/i
  ].freeze

  scope :verified, -> { where(verified: true) }
  scope :normalizable, -> { where.not(normalized_name: nil) }

  class << self
    # Matches patterns that can never be normalized (anonymous, traditional, etc.)
    # These are cached with nil to prevent re-processing.
    def known_unnormalizable?(name)
      return false if name.blank?
      UNNORMALIZABLE_PATTERNS.any? { |pattern| name.match?(pattern) }
    end

    # Does this look like a real composer name?
    # Used to filter garbage that shouldn't be cached.
    def looks_like_name?(str)
      return false if str.blank?
      return false if str.length > 50
      return false if str.split.size > 5
      return false unless str.match?(/\A[\p{L}\s.\-,'']+\z/)
      return false unless str.match?(/\A\p{Lu}/)
      true
    end

    # Should this original string be cached in ComposerMapping?
    # - Unnormalizable patterns: YES (cached with nil)
    # - Name-like strings: YES (cached with AI result)
    # - Garbage: NO (context-dependent, don't pollute cache)
    def cacheable?(original)
      return false if original.blank?
      known_unnormalizable?(original) || looks_like_name?(original)
    end

    # Look up cached normalized form. Returns nil if not found OR if cached as nil.
    def lookup(name)
      find_by(original_name: name)&.normalized_name
    end

    # Check if we've already processed this name (regardless of result)
    def processed?(name)
      exists?(original_name: name)
    end

    # Register a mapping result. Only caches if cacheable.
    # Returns the mapping record, or nil if not cacheable.
    def register(original:, normalized:, source:, verified: false)
      return nil unless cacheable?(original)

      find_or_create_by!(original_name: original) do |mapping|
        mapping.normalized_name = normalized
        mapping.source = source
        mapping.verified = verified
      end
    rescue ActiveRecord::RecordNotUnique
      find_by(original_name: original)
    end
  end
end
