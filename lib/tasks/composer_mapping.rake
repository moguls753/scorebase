# frozen_string_literal: true

namespace :composers do
  desc "Seed IMSLP priority composers into ComposerMapping table"
  task seed_priority: :environment do
    # Get priority composers from IMSLP importer
    priority = ImslpImporter::PRIORITY_COMPOSERS.map { |c| c.tr("_", " ") }

    puts "Seeding #{priority.size} IMSLP priority composers..."

    created = 0
    priority.each do |composer|
      mapping = ComposerMapping.find_or_create_by!(original_name: composer) do |m|
        m.normalized_name = composer  # Self-mapping (already normalized)
        m.source = "imslp_priority"
        m.verified = true
      end
      created += 1 if mapping.previously_new_record?
    end

    puts "Created #{created} new mappings (#{priority.size - created} already existed)"
  end

  # NOTE: backfill task was removed - it created problematic self-mappings
  # that caused slug collisions (e.g., "Händel" vs "Handel").
  # Use AI normalization (ComposerNormalizer) instead.

  desc "Mark scores as normalized if composer is in ComposerMapping"
  task mark_normalized: :environment do
    puts "Marking scores as normalized based on ComposerMapping..."

    # Get all normalized names from mapping
    known_composers = ComposerMapping.normalizable.pluck(:normalized_name).uniq

    puts "Found #{known_composers.size} known composers in mapping"

    # Update pending scores that have these composers
    updated = Score.composer_pending
                   .where(composer: known_composers)
                   .update_all(composer_status: "normalized")

    puts "Marked #{updated} scores as normalized"
  end

  desc "Run composer mapping setup: seed priority composers, mark normalized"
  task setup: :environment do
    Rake::Task["composers:seed_priority"].invoke
    Rake::Task["composers:mark_normalized"].invoke
  end
end
