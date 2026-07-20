# frozen_string_literal: true

# Recomputes title_search_normalized / composer_search_normalized from their
# source columns. Both drifted because bulk update_all rewrites skip the
# before_save that derives them. Safe to re-run; in-sync rows are skipped.
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

      Score.upsert_all(updates, update_only: %i[title_search_normalized composer_search_normalized])
      stats[:updated] += updates.size
    end

    Rails.logger.info("BackfillSearchColumnsJob complete: #{stats}")
    stats
  end
end
