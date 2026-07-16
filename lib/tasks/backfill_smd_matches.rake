namespace :scores do
  desc "Match free scores to professional SMD editions (DRY_RUN=1 prints raw matches ignoring suppressions, writes nothing)"
  task backfill_smd_matches: :environment do
    if ENV["DRY_RUN"] == "1"
      index = SmdMatchFinder.build_index(
        Score.active.where(source: "smd").deduplicate_arrangements
             .pluck(:id, :title, :composer, :artist, :price_usd)
      )
      smd = index.values.flatten(1).index_by(&:first)
      Score.active.where.not(source: "smd").in_batches do |batch|
        batch.pluck(:id, :title, :composer).each do |id, title, composer|
          SmdMatchFinder.matches_for(title, composer, index).first(SmdMatchFinder::MAX_MATCHES).each do |smd_id|
            row = smd[smd_id]
            puts [ id, title, composer, smd_id, row[1], row[2].presence || row[3], row[4] ].join("\t")
          end
        end
      end
    else
      # .new.perform runs synchronously and returns the stats hash (and raises loudly on
      # error); perform_now would route a transient failure through retry_on and re-enqueue.
      stats = BackfillSmdMatchesJob.new.perform
      puts "Matches done: #{stats[:matched_scores]} free scores matched, " \
           "#{stats[:created]} links created, #{stats[:removed]} removed, " \
           "#{stats[:unchanged]} unchanged."
    end
  end
end
