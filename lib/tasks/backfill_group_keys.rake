namespace :scores do
  desc "Backfill group_key for SMD arrangements"
  task backfill_group_keys: :environment do
    scope = Score.where(source: "smd")
    total = scope.count

    puts "Backfilling group_key for #{total} SMD scores..."

    # Pass 1: Assign group_keys to parts (scores with instrument suffix)
    puts "\nPass 1: Processing parts..."
    updated = 0
    grouped = 0

    scope.find_each.with_index do |score, i|
      group_key = Score.derive_group_key(score.clean_title, score.thumbnail_url)
      if score.group_key != group_key
        score.update_column(:group_key, group_key)
        updated += 1
      end
      grouped += 1 if group_key.present?
      print "\r#{i + 1}/#{total} (#{updated} updated, #{grouped} grouped)" if ((i + 1) % 500).zero?
    end
    puts "\rPass 1 done: #{updated} updated, #{grouped} have group_key"

    # Pass 2: Assign group_keys to bundle products (no instrument suffix but siblings exist)
    puts "\nPass 2: Processing bundles..."
    bundles_updated = 0

    scope.where(group_key: nil).find_each do |score|
      group_key = Score.derive_bundle_group_key(score.clean_title, score.thumbnail_url)
      if group_key
        score.update_column(:group_key, group_key)
        bundles_updated += 1
      end
    end
    puts "Pass 2 done: #{bundles_updated} bundles grouped"

    puts "\nTotal: #{updated + bundles_updated} updated, #{grouped + bundles_updated} have group_key"
  end
end
