# frozen_string_literal: true

namespace :normalize do
  desc "Normalize composers using Gemini AI (LIMIT=100 for testing)"
  task composers: :environment do
    api_key = ENV.fetch("GEMINI_API_KEY") { abort "Set GEMINI_API_KEY" }
    limit = ENV["LIMIT"]&.to_i

    GeminiComposerNormalizer.new(api_key: api_key, limit: limit).normalize!
  end

  desc "Reset normalization cache"
  task reset: :environment do
    if AppSetting.find_by(key: "composer_cache")&.destroy
      puts "Progress reset."
    else
      puts "No progress found."
    end
  end
end
