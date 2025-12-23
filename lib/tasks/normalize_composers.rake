# frozen_string_literal: true

namespace :normalize do
  desc "Normalize composers using AI. LIMIT=1000 (omit for all)"
  task composers: :environment do
    limit = ENV["LIMIT"]&.to_i
    NormalizeComposersJob.perform_now(limit: limit)
  end

  desc "Reset composer normalization (marks all as pending)"
  task reset: :environment do
    count = Score.update_all(composer_status: "pending")
    puts "Reset #{count} scores to composer_status=pending"
  end
end
