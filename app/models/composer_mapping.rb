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

  # Patterns that ALWAYS map to nil - cache immediately, no AI needed
  KNOWN_UNCACHEABLE = [
    /an[oóô]n/i,                  # anonymous, anonymus, anónimo, anônimo, etc.
    /\bunknown\b/i,
    /\btraditional\b/i,
    /\bfolk\b/i,
    /\bvarious\b/i,
  ].freeze

  scope :verified, -> { where(verified: true) }
  scope :normalizable, -> { where.not(normalized_name: nil) }

  class << self
    # Does this look like a real composer name?
    # Only Unicode letters, spaces, dots, commas, hyphens, apostrophes
    # Must start with capital, reasonable length, not too many words
    def looks_like_name?(str)
      return false if str.blank?
      return false if str.length > 50
      return false if str.split.size > 5              # names rarely exceed 5 words
      return false unless str.match?(/\A[\p{L}\s.\-,'']+\z/)
      return false unless str.match?(/\A\p{Lu}/)
      true
    end

    def known_uncacheable?(name)
      return false if name.blank?
      KNOWN_UNCACHEABLE.any? { |p| name.match?(p) }
    end

    def cacheable?(original)
      return false if original.blank?
      return true if known_uncacheable?(original)
      looks_like_name?(original)
    end

    # Look up normalized form
    def normalize(name)
      return nil if name.blank?
      find_by(original_name: name)&.normalized_name
    end

    # Check if already processed
    def attempted?(name)
      exists?(original_name: name)
    end

    # Register a mapping (respects cacheability)
    def register(original:, normalized:, source:, verified: false)
      return nil unless cacheable?(original)

      find_or_create_by!(original_name: original) do |m|
        m.normalized_name = normalized
        m.source = source
        m.verified = verified
      end
    rescue ActiveRecord::RecordNotUnique
      find_by(original_name: original)
    end
  end
end
