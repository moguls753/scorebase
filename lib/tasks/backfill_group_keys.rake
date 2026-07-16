namespace :scores do
  desc "Backfill group_key + is_group_representative for SMD arrangements (runs BackfillGroupKeysJob)"
  task backfill_group_keys: :environment do
    # .new.perform runs synchronously and returns the stats hash (and raises loudly on
    # error); perform_now would route a transient failure through retry_on and re-enqueue.
    stats = BackfillGroupKeysJob.new.perform
    puts "Backfill done: #{stats[:part_keys]} part keys updated, " \
         "#{stats[:bundle_keys]} bundle keys updated, " \
         "#{stats[:parent_keys]} set listings absorbed, " \
         "#{stats[:representatives]} representatives marked."
  end
end
