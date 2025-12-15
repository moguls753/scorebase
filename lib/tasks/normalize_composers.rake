# frozen_string_literal: true

namespace :normalize do
  desc "Normalize composers using Groq AI (LIMIT=1000 controls batch size, e.g., 1000 = 10 API calls)"
  task composers: :environment do
    limit = ENV["LIMIT"]&.to_i

    GroqComposerNormalizer.new(limit: limit).normalize!
  end

  desc "Reset normalization progress (marks all scores as pending)"
  task reset: :environment do
    count = Score.update_all(normalization_status: "pending")
    puts "Reset #{count} scores to pending."
  end
end
