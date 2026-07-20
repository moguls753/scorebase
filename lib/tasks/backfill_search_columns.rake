namespace :scores do
  desc "Recompute title/composer search columns from their source columns. LIMIT=1000 (omit for all)"
  task backfill_search_columns: :environment do
    # .new.perform runs synchronously and returns the stats hash (and raises loudly on
    # error); perform_now would route a transient failure through retry_on and re-enqueue.
    stats = BackfillSearchColumnsJob.new.perform(limit: ENV["LIMIT"]&.to_i)
    puts "Backfill done: #{stats[:examined]} examined, #{stats[:updated]} rewritten."
  end
end
