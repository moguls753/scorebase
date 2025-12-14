# frozen_string_literal: true

namespace :normalize do
  desc "Normalize composers using Groq AI (LIMIT=1000 controls batch size, e.g., 1000 = 10 API calls)"
  task composers: :environment do
    limit = ENV["LIMIT"]&.to_i

    GroqComposerNormalizer.new(limit: limit).normalize!
  end

  desc "Reset normalization progress (marks all scores as unattempted)"
  task reset: :environment do
    count = Score.update_all(composer_normalized: false, composer_attempted: false)
    puts "Reset #{count} scores to unattempted."

    # Optional: also clear old cache if it exists
    if AppSetting.find_by(key: "composer_cache")&.destroy
      puts "Cleared old composer_cache."
    end
  end
end
