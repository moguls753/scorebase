# frozen_string_literal: true

namespace :normalize do
  desc "Normalize composers using AI (auto-fallback between Groq and Gemini). LIMIT=1000 controls batch size."
  task composers: :environment do
    limit = ENV["LIMIT"]&.to_i
    ComposerNormalizer.new(limit: limit).normalize!
  end

  desc "Reset composer normalization progress (marks all scores as pending)"
  task reset: :environment do
    count = Score.update_all(composer_status: "pending")
    puts "Reset #{count} scores to composer_status=pending."
  end
end
