# frozen_string_literal: true

namespace :normalize do
  desc "Migrate composer_cache from AppSetting to composer_normalized flag"
  task migrate_cache: :environment do
    cache = AppSetting.get("composer_cache")

    if cache.nil? || cache.empty?
      puts "No composer_cache found in AppSettings. Nothing to migrate."
      exit
    end

    puts "Found #{cache.count} cached composer mappings."
    puts "Migrating to composer_normalized flag...\n"

    migrated = 0
    cache.each do |original_composer, normalized_composer|
      scores = Score.where(composer_attempted: false)
                    .where("composer = ? OR composer = ?", original_composer, normalized_composer)

      count = scores.count
      next if count.zero?

      if normalized_composer
        # Update to normalized name and mark as successfully normalized
        scores.update_all(
          composer: normalized_composer,
          composer_normalized: true,
          composer_attempted: true
        )
        puts "  [#{count}] #{original_composer[0..30].ljust(33)} -> #{normalized_composer}"
      else
        # Mark as attempted but not normalizable (unknown)
        scores.update_all(
          composer_normalized: false,
          composer_attempted: true
        )
        puts "  [#{count}] #{original_composer[0..30].ljust(33)} -> (unknown, not normalizable)"
      end

      migrated += count
    end

    puts "\n#{"=" * 50}"
    puts "Migration complete!"
    puts "Total scores migrated: #{migrated}"
    puts "\nYou can now safely delete the old cache with:"
    puts "  AppSetting.find_by(key: 'composer_cache')&.destroy"
  end
end
