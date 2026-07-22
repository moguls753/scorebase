namespace :scores do
  desc "Match free scores to professional SMD editions (DRY_RUN=1 prints raw matches ignoring suppressions, writes nothing)"
  task backfill_smd_matches: :environment do
    if ENV["DRY_RUN"] == "1"
      cap = SmdMatchFinder::MAX_MATCHES
      matches = BackfillSmdMatchesJob.new.compute_matches.transform_values { |ids| ids.first(cap) }
      free = Score.where(id: matches.keys).select(:id, :title, :composer).index_by(&:id)
      smd  = Score.where(id: matches.values.flatten).select(:id, :title, :smd_category, :price_usd).index_by(&:id)
      matches.each do |free_id, smd_ids|
        f = free[free_id]
        smd_ids.each do |smd_id|
          s = smd[smd_id]
          puts [ f.id, f.title, f.composer, smd_id, s.title, s.smd_category, s.price_usd ].join("\t")
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
