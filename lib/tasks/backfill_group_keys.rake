namespace :scores do
  desc "Backfill group_key and is_group_representative for SMD arrangements"
  # Run after importing new SMD scores to update grouping and representatives
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

    # Pass 3: Set is_group_representative for each group
    # Prefers: Full Score > Conductor Score > alphabetically first
    puts "\nPass 3: Setting is_group_representative..."

    # Reset all first
    Score.where.not(is_group_representative: nil).update_all(is_group_representative: nil)

    # Single UPDATE with subquery - finds representative for each group in one query
    reps_set = Score.connection.update(<<~SQL.squish)
      UPDATE scores SET is_group_representative = 1
      WHERE id IN (
        SELECT (
          SELECT s2.id FROM scores s2
          WHERE s2.group_key = groups.group_key
            AND s2.deleted_at IS NULL
          ORDER BY
            CASE
              WHEN s2.clean_title LIKE '%Full Score%' THEN 0
              WHEN s2.clean_title LIKE '%Conductor%' THEN 1
              ELSE 2
            END,
            s2.clean_title
          LIMIT 1
        )
        FROM (SELECT DISTINCT group_key FROM scores WHERE group_key IS NOT NULL AND deleted_at IS NULL) groups
      )
    SQL
    puts "Pass 3 done: #{reps_set} representatives set"

    puts "\nTotal: #{updated + bundles_updated} group_keys updated, #{reps_set} representatives marked"
  end
end
