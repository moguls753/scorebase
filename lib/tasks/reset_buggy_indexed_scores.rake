# frozen_string_literal: true

# One-time data fix: reset the 141 scores indexed under commit ed0e0ef (2026-01-12),
# whose `SearchTextGenerator#difficulty_label` ignored `pedagogical_grade` and fed
# "easy" / "beginner" labels into the LLM prompt for Grade 6-8 pieces. The current
# HEAD generator (post 0445dbb) prioritizes `pedagogical_grade`, so these rows must
# be regenerated.
#
# All 141 rows were indexed at 2026-01-12 10:57:49 UTC and are the only rows in
# rag_status=indexed. Verified on 2026-04-27.
#
# Effect (per row):
#   rag_status                = "ready"
#   search_text               = nil
#   search_text_generated_at  = nil
#   indexed_at                = nil
#
# Forensic snapshot (id, title, composer, pedagogical_grade, search_text,
# search_text_generated_at, indexed_at) is written to tmp/ on both dry-run and
# apply, so the original 141 search_texts can be recovered if needed.
#
# ChromaDB note: this repo deploys no RAG service via Kamal — there is no
# ChromaDB to wipe in tandem. If a manually-stood-up Chroma exists on the host,
# it must be cleared separately (the indexer is append-only and will skip these
# IDs on the next run otherwise).
#
# This task is intended to run once. It can be deleted after it has run cleanly
# on prod.
#
# Usage:
#   bin/rails rag:reset_buggy_indexed_scores              # dry-run (default)
#   bin/rails rag:reset_buggy_indexed_scores APPLY=true   # actually mutate
#
namespace :rag do
  desc "Reset the 141 buggy indexed scores (one-time). DRY-RUN unless APPLY=true."
  task reset_buggy_indexed_scores: :environment do
    apply = ENV["APPLY"] == "true"

    candidates = Score.where(rag_status: "indexed")
    total = candidates.count

    puts "Mode: #{apply ? 'APPLY (will mutate)' : 'DRY RUN (no changes)'}"
    puts "Found #{total} rows in rag_status=indexed."
    puts

    if total.zero?
      puts "Nothing to reset. Exiting."
      next
    end

    rows = candidates.pluck(
      :id, :title, :composer, :pedagogical_grade,
      :search_text, :search_text_generated_at, :indexed_at
    )

    log_dir = Rails.root.join("tmp")
    log_dir.mkpath
    log_path = log_dir.join("reset_buggy_indexed_scores_#{apply ? 'applied' : 'dryrun'}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json")

    log_payload = {
      run_at: Time.current.iso8601,
      mode: apply ? "applied" : "dry_run",
      row_count: total,
      rows: rows.map { |id, title, composer, grade, text, gen_at, idx_at|
        {
          id: id,
          title: title,
          composer: composer,
          pedagogical_grade: grade,
          old_search_text: text,
          old_search_text_generated_at: gen_at&.iso8601,
          old_indexed_at: idx_at&.iso8601
        }
      }
    }
    log_path.write(JSON.pretty_generate(log_payload))
    puts "Forensic snapshot: #{log_path}"
    puts

    unless apply
      puts "Sample of rows that would be reset (first 5):"
      rows.first(5).each do |id, title, composer, grade, *_|
        puts "  id=#{id.to_s.rjust(7)}  grade=#{grade.to_s.ljust(12)}  composer=#{composer.to_s.truncate(30).ljust(30)}  title=#{title.to_s.truncate(40)}"
      end
      puts
      puts "Re-run with APPLY=true to mutate."
      next
    end

    # APPLY ─────────────────────────────────────────────────────────────────
    reset_count = candidates.update_all(
      rag_status: "ready",
      search_text: nil,
      search_text_generated_at: nil,
      indexed_at: nil
    )

    puts "Done."
    puts "  Reset #{reset_count} rows from indexed → ready (search_text/generated_at/indexed_at nulled)."
    puts
    puts "Final rag_status counts:"
    Score.group(:rag_status).count.sort.each { |k, v| puts "  #{k.ljust(12)}: #{v}" }
  end
end
