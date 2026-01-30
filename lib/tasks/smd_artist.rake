# frozen_string_literal: true

namespace :smd do
  desc "Backfill artist field for SMD scores (non-Klassik only)"
  task backfill_artist: :environment do
    puts "Backfilling artist field for SMD scores..."

    # Non-Klassik SMD scores get artist = composer
    non_klassik = Score.where(source: "smd")
                       .where.not("tags LIKE ?", "%Klassik%")
                       .where(artist: nil)

    non_klassik_count = non_klassik.count
    puts "Found #{non_klassik_count} non-Klassik SMD scores to update"

    if non_klassik_count > 0
      non_klassik.update_all("artist = composer")
      puts "Set artist = composer for #{non_klassik_count} scores"
    end

    # Klassik SMD scores keep artist = nil (already nil by default)
    klassik_count = Score.where(source: "smd")
                         .where("tags LIKE ?", "%Klassik%")
                         .count
    puts "#{klassik_count} Klassik SMD scores left with artist = nil"

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
