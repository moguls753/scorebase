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

  desc "Backfill ComposerMapping from existing normalized scores"
  task backfill: :environment do
    puts "Backfilling from normalized scores..."

    # Get all distinct composers from normalized scores
    composers = Score.normalized
                     .where.not(composer: nil)
                     .distinct
                     .pluck(:composer)

    puts "Found #{composers.size} distinct normalized composers"

    created = 0
    skipped = 0
    composers.each do |composer|
      next unless ComposerMapping.cacheable?(composer)

      mapping = ComposerMapping.find_or_create_by!(original_name: composer) do |m|
        m.normalized_name = composer
        m.source = "backfill"
        m.verified = false
      end
      if mapping.previously_new_record?
        created += 1
      else
        skipped += 1
      end
    rescue ActiveRecord::RecordNotUnique
      skipped += 1
    end

    puts "Created #{created} new mappings, #{skipped} already existed"
  end

  desc "Mark scores as normalized if composer is in ComposerMapping"
  task mark_normalized: :environment do
    puts "Marking scores as normalized based on ComposerMapping..."

    # Get all normalized names from mapping
    known_composers = ComposerMapping.normalizable.pluck(:normalized_name).uniq

    puts "Found #{known_composers.size} known composers in mapping"

    # Update pending scores that have these composers
    updated = Score.pending
                   .where(composer: known_composers)
                   .update_all(normalization_status: "normalized")

    puts "Marked #{updated} scores as normalized"
  end

  desc "Run all composer mapping tasks: seed, backfill, mark"
  task setup: :environment do
    Rake::Task["composers:seed_priority"].invoke
    Rake::Task["composers:backfill"].invoke
    Rake::Task["composers:mark_normalized"].invoke
  end
end
