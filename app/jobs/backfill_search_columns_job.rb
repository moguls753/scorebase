# frozen_string_literal: true

# Recomputes title_search_normalized / composer_search_normalized from their
# source columns.
#
# Both drifted the same way: a bulk `update_all` rewrote `title` (the May 2026
# marketing-tail cleanup) and `composer` (ComposerNormalizer), and update_all
# skips the before_save that derives these. The columns kept their pre-rewrite
# values, so the FTS index describes titles and names the site no longer shows.
#
# Purely local — no network, no LLM. Safe to re-run; rows already in sync are
# skipped, so a second pass is a no-op.
class BackfillSearchColumnsJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 1000

  def perform(limit: nil)
    stats = { examined: 0, updated: 0 }
    scope = Score.all
    scope = scope.limit(limit) if limit

    scope.in_batches(of: BATCH_SIZE) do |batch|
      updates = batch.filter_map do |score|
        title = Score.normalize_for_search(score.title)
        composer = Score.normalize_for_search(score.composer)
        stats[:examined] += 1

        next if score.title_search_normalized == title &&
                score.composer_search_normalized == composer

        { id: score.id, title_search_normalized: title, composer_search_normalized: composer }
      end

      next if updates.empty?

      # One statement per batch. The FTS triggers are SQL-level so they still
      # fire, which is the point — the search index is what we are repairing.
      Score.upsert_all(updates, update_only: %i[title_search_normalized composer_search_normalized])
      stats[:updated] += updates.size
    end

    Rails.logger.info("BackfillSearchColumnsJob complete: #{stats}")
    stats
  end
end
