# frozen_string_literal: true

namespace :gallery do
  desc "Show ScorePage deletion log summary"
  task deletion_log: :environment do
    puts "=" * 70
    puts "ScorePage Deletion Log"
    puts "=" * 70

    if ScorePageDeletionLog.count.zero?
      puts "No deletions logged yet."
      puts "(The trigger was just added - it will catch future deletions)"
      next
    end

    summary = ScorePageDeletionLog.summary
    puts "Total deletions: #{summary[:total]}"
    puts "  From trigger (delete_all/CASCADE): #{summary[:from_trigger]}"
    puts "  From callback (destroy):           #{summary[:from_callback]}"
    puts "Unique scores affected: #{summary[:unique_scores_affected]}"
    puts "First deletion: #{summary[:first_deletion]}"
    puts "Last deletion:  #{summary[:last_deletion]}"
    puts "Today: #{summary[:today]}"

    # Analysis: if trigger >> callback, something is using delete_all or CASCADE
    if summary[:from_trigger] > summary[:from_callback] * 2
      puts "\n!! WARNING: Most deletions bypassed Rails (delete_all or CASCADE)"
    end

    puts "\n" + "-" * 70
    puts "Timeline by hour (source breakdown):"
    ScorePageDeletionLog
      .select("strftime('%Y-%m-%d %H:00', deleted_at) as hour, source, COUNT(*) as cnt")
      .group("hour, source")
      .order("hour DESC")
      .limit(48)
      .each { |r| puts "  #{r.hour} [#{r.source.ljust(8)}]: #{r.cnt}" }

    puts "\n" + "-" * 70
    puts "Recent deletions with context:"
    ScorePageDeletionLog.from_callback.recent.limit(5).each do |log|
      puts "\n  #{log.deleted_at} - score ##{log.score_id}, page #{log.page_number}"
      puts "  Call stack:"
      log.context&.split("\n")&.first(5)&.each { |line| puts "    #{line}" }
    end

    # Check for bulk deletions (many in same second = likely delete_all)
    bulk = ScorePageDeletionLog
      .from_trigger
      .group(:deleted_at)
      .having("COUNT(*) > 100")
      .count

    if bulk.any?
      puts "\n" + "-" * 70
      puts "BULK DELETIONS DETECTED (>100 in same second):"
      bulk.first(10).each { |time, count| puts "  #{time}: #{count} pages" }
    end
  end

  desc "Clear deletion log (after investigating)"
  task clear_deletion_log: :environment do
    count = ScorePageDeletionLog.count
    print "Delete #{count} deletion log entries? (y/N): "
    if $stdin.gets&.strip&.downcase == "y"
      ScorePageDeletionLog.delete_all
      puts "Cleared."
    else
      puts "Aborted."
    end
  end
end
