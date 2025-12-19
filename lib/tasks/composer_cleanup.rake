# frozen_string_literal: true

namespace :composers do
  desc "Fix composer name variants to use canonical forms"
  task cleanup: :environment do
    puts "Composer Cleanup"
    puts "=" * 70

    # Known variants that should map to IMSLP priority canonical forms
    # Format: "variant" => "canonical"
    CANONICAL_REMAPS = {
      # German forms -> English canonical
      "Händel, Georg Friedrich" => "Handel, George Frideric",
      "Handel, Georg Friedrich" => "Handel, George Frideric",
      "Schütz, Heinrich" => "Schutz, Heinrich",

      # Extended names -> Standard forms
      "Vivaldi, Antonio Lucio" => "Vivaldi, Antonio",
      "Grieg, Edvard Hagerup" => "Grieg, Edvard",
      "Tchaikovsky, Pjotr Iljitsch" => "Tchaikovsky, Pyotr",

      # Abbreviation variants
      "Elgar, E." => "Elgar, Edward",
      "Laybourn, W B" => "Laybourn, W.B.",
      "Skinner, J S" => "Skinner, J.S."
    }.freeze

    total_scores_updated = 0
    total_mappings_fixed = 0

    CANONICAL_REMAPS.each do |variant, canonical|
      scores_count = Score.where(composer: variant).count
      next if scores_count.zero?

      puts "\n#{variant} -> #{canonical}"

      # Update scores
      updated = Score.where(composer: variant).update_all(composer: canonical)
      puts "  Updated #{updated} scores"
      total_scores_updated += updated

      # Update or delete the bad ComposerMapping
      bad_mapping = ComposerMapping.find_by(normalized_name: variant)
      if bad_mapping
        # Re-point it to canonical instead of deleting (preserves original_name lookups)
        bad_mapping.update!(normalized_name: canonical)
        puts "  Fixed ComposerMapping ##{bad_mapping.id}"
        total_mappings_fixed += 1
      end

      # Ensure canonical mapping exists
      ComposerMapping.find_or_create_by!(original_name: canonical) do |m|
        m.normalized_name = canonical
        m.source = "cleanup"
        m.verified = true
      end
    end

    puts "\n" + "=" * 70
    puts "Summary:"
    puts "  Scores updated: #{total_scores_updated}"
    puts "  Mappings fixed: #{total_mappings_fixed}"
  end

  desc "Show current slug collisions in ComposerMapping"
  task check_collisions: :environment do
    puts "Checking for slug collisions..."
    puts "=" * 70

    by_slug = Hash.new { |h, k| h[k] = [] }
    ComposerMapping.normalizable.find_each do |m|
      by_slug[m.normalized_name.parameterize] << m.normalized_name
    end

    collisions = by_slug.select { |_, names| names.uniq.size > 1 }

    if collisions.empty?
      puts "No collisions found."
    else
      puts "Found #{collisions.size} slug collisions:\n\n"
      collisions.each do |slug, names|
        puts "Slug: #{slug}"
        names.uniq.each do |name|
          count = Score.where(composer: name).count
          puts "  - #{name} (#{count} scores)"
        end
        puts
      end
    end
  end
end
