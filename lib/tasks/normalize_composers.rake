# frozen_string_literal: true

namespace :normalize do
  desc "Normalize composers using Groq AI (LIMIT=100 for testing)"
  task composers: :environment do
    limit = ENV["LIMIT"]&.to_i

    GroqComposerNormalizer.new(limit: limit).normalize!
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
