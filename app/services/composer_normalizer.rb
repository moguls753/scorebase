# frozen_string_literal: true

# Unified composer normalizer with automatic provider fallback
class ComposerNormalizer
  PROVIDERS = [
    { credential: [:groq, :api_key], class: GroqComposerNormalizer },
    { credential: [:gemini, :api_key], class: GeminiComposerNormalizer }
  ].freeze

  def initialize(limit: nil)
    @limit = limit
  end

  def normalize!
    available = PROVIDERS.select { |p| Rails.application.credentials.dig(*p[:credential]).present? }

    if available.empty?
      puts "No API keys configured. Add groq.api_key or gemini.api_key to Rails credentials."
      return
    end

    puts "Available providers: #{available.map { |p| p[:class].name }.join(", ")}\n\n"

    available.each do |provider|
      begin
        puts "Trying #{provider[:class].name}..."
        provider[:class].new(limit: @limit).normalize!
        return # Success
      rescue ComposerNormalizerBase::QuotaExceededError
        puts "\n#{provider[:class].name} quota exceeded, trying next provider...\n\n"
        next
      rescue => e
        puts "\n#{provider[:class].name} failed: #{e.message}, trying next provider...\n\n"
        next
      end
    end

    puts "\nAll providers exhausted or quota exceeded."
  end
end
