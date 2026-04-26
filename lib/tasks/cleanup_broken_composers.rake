# frozen_string_literal: true

# One-time data fix: NULL out composer values that came from broken imports.
#
# Patterns targeted:
#   - composer is the literal string "null" (case-insensitive)
#   - composer is digits-only (e.g., "1", "42")
#   - composer is unreasonably long (> 100 chars — usually arranger concatenations)
#   - composer contains a newline character (truncated CSV import)
#
# Verified scope on 2026-04-26 dev DB (synced from prod):
#   152 rows total in rag_status=ready match these patterns; ~15 will be demoted
#   to rag_status=pending after cleanup because they have no other identity.
#
# This task is intended to run once. After it has run cleanly on prod and
# subsequent imports stop reintroducing these patterns, the task can be deleted.
#
# Usage:
#   bin/rails rag:cleanup_broken_composers           # dry-run (default)
#   bin/rails rag:cleanup_broken_composers APPLY=true # actually mutate
#
namespace :rag do
  desc "Cleanup broken composer values (one-time). DRY-RUN unless APPLY=true."
  task cleanup_broken_composers: :environment do
    apply = ENV["APPLY"] == "true"

    candidates = Score.where(rag_status: "ready").where(
      "LOWER(composer) = 'null' OR " \
      "(composer GLOB '[0-9]*' AND composer NOT GLOB '*[^0-9]*') OR " \
      "LENGTH(composer) > 100 OR " \
      "composer LIKE '%' || char(10) || '%'"
    )

    total = candidates.count
    puts "Mode: #{apply ? 'APPLY (will mutate)' : 'DRY RUN (no changes)'}"
    puts "Found #{total} rows in rag_status=ready with broken composer values."
    puts

    if total.zero?
      puts "Nothing to clean. Exiting."
      next
    end

    # Snapshot what will change, for the log file
    rows = candidates.pluck(:id, :composer, :title, :genre, :genre_status, :voicing, :voicing_status, :instruments, :instruments_status)

    # Predict status demotions (without mutating)
    demote_ids = rows.filter_map do |id, composer, title, genre, genre_status, voicing, voicing_status, instruments, instruments_status|
      # Simulate ready_for_rag? after composer = nil
      has_voicing     = voicing_status == "normalized" && voicing.present?
      has_instruments = instruments_status == "normalized" && instruments.present?
      has_genre       = genre_status == "normalized" && genre.present?

      identity_after_cleanup = has_genre  # composer becomes nil, so only genre carries identity
      instrumentation        = has_voicing || has_instruments

      id unless instrumentation && identity_after_cleanup
    end

    puts "Will null composer on #{total} rows."
    puts "Will demote #{demote_ids.size} rows from rag_status=ready to rag_status=pending"
    puts "  (these have no other identity once composer is nil)."
    puts

    # Log file (always written, even on dry-run, for audit)
    log_dir = Rails.root.join("tmp")
    log_dir.mkpath
    log_path = log_dir.join("cleanup_broken_composers_#{apply ? 'applied' : 'dryrun'}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json")

    log_payload = {
      run_at: Time.current.iso8601,
      mode: apply ? "applied" : "dry_run",
      rows_value_cleaned: rows.map { |id, composer, title, *_| { id: id, old_composer: composer, title: title } },
      rows_demoted_to_pending: demote_ids
    }
    log_path.write(JSON.pretty_generate(log_payload))
    puts "Log: #{log_path}"
    puts

    unless apply
      puts "Sample of rows that would be cleaned (first 10):"
      rows.first(10).each do |id, composer, title, *_|
        puts "  id=#{id.to_s.rjust(7)}  composer=#{composer.inspect.truncate(60)}  title=#{title.to_s.truncate(40)}"
      end
      puts
      puts "Re-run with APPLY=true to mutate."
      next
    end

    # APPLY ─────────────────────────────────────────────────────────────────
    cleaned_count = candidates.update_all(composer: nil)
    demoted_count = Score.where(id: demote_ids).update_all(rag_status: "pending")

    puts "Done."
    puts "  Composer nulled on #{cleaned_count} rows."
    puts "  Status demoted to pending on #{demoted_count} rows."
    puts
    puts "Final rag_status counts:"
    Score.group(:rag_status).count.sort.each { |k, v| puts "  #{k.ljust(12)}: #{v}" }
  end
end
