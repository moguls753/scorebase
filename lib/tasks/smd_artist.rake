# frozen_string_literal: true

namespace :smd do
  desc "Backfill artist field for SMD scores (non-Klassik/Barock only)"
  task backfill_artist: :environment do
    puts "Backfilling artist field for SMD scores..."

    # Non-Klassik/Barock SMD scores get artist = composer
    non_classical = Score.where(source: "smd")
                         .where.not("tags LIKE ?", "%Klassik%")
                         .where.not("tags LIKE ?", "%Barock%")
                         .where(artist: nil)

    non_classical_count = non_classical.count
    puts "Found #{non_classical_count} non-Klassik/Barock SMD scores to update"

    if non_classical_count > 0
      non_classical.update_all("artist = composer")
      puts "Set artist = composer for #{non_classical_count} scores"
    end

    # Klassik/Barock SMD scores keep artist = nil
    excluded_count = Score.where(source: "smd")
                          .where("tags LIKE ? OR tags LIKE ?", "%Klassik%", "%Barock%")
                          .count
    puts "#{excluded_count} Klassik/Barock SMD scores left with artist = nil"

    puts "Done!"
  end

  desc "Show artist field stats for SMD scores"
  task artist_stats: :environment do
    smd_total = Score.where(source: "smd").count
    with_artist = Score.where(source: "smd").where.not(artist: nil).count
    without_artist = Score.where(source: "smd").where(artist: nil).count

    puts "SMD Scores: #{smd_total}"
    puts "  With artist:    #{with_artist}"
    puts "  Without artist: #{without_artist}"
    puts ""
    puts "Top 20 artists by score count:"
    Score.where(source: "smd")
         .where.not(artist: nil)
         .group(:artist)
         .order("count_all desc")
         .limit(20)
         .count
         .each { |name, count| puts "  #{count.to_s.rjust(5)} - #{name}" }
  end
end
