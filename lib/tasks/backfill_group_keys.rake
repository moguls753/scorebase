namespace :scores do
  desc "Backfill group_key for SMD arrangements"
  task backfill_group_keys: :environment do
    scope = Score.where(source: "smd")
    total = scope.count

    puts "Backfilling group_key for #{total} SMD scores..."

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

    puts "\rDone: #{total} processed, #{updated} updated, #{grouped} have group_key"
  end
end
