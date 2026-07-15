class BackfillGroupKeysJob < ApplicationJob
  queue_as :default

  # Idempotent, so a transient SQLite "database is busy" lock retries from scratch
  # (re-running is cheap: unchanged rows are skipped) rather than leaving rows keyed
  # but representative-less — hidden from browse/hub listings — until the next nightly run.
  retry_on ActiveRecord::StatementInvalid, wait: :polynomially_longer, attempts: 3

  # group_key and is_group_representative are DERIVED from title + thumbnail_url,
  # so this is safe to re-run any time: unchanged rows are skipped, changed rows
  # are corrected, and stale keys are cleared. Scheduled nightly (config/recurring.yml)
  # and callable via `bin/rails scores:backfill_group_keys`.
  def perform
    scope = Score.where(source: "smd")

    stats = {
      part_keys: assign_part_keys(scope),
      bundle_keys: assign_bundle_keys(scope),
      representatives: assign_representatives
    }
    logger.info "[BackfillGroupKeys] #{stats}"
    stats
  end

  private

  # Parts ("Title - Instrument"): pure derivation from the row's own fields.
  def assign_part_keys(scope)
    updated = 0
    scope.find_each do |score|
      key = Score.derive_group_key(score.title, score.thumbnail_url)
      next if score.group_key == key

      score.update_column(:group_key, key)
      updated += 1
    end
    updated
  end

  # Bundles ("Title (arr. X)" with no instrument suffix): only match once the
  # sibling parts already carry the key, so this must run after assign_part_keys.
  def assign_bundle_keys(scope)
    updated = 0
    scope.where(group_key: nil).find_each do |score|
      key = Score.derive_bundle_group_key(score.title, score.thumbnail_url)
      next unless key

      score.update_column(:group_key, key)
      updated += 1
    end
    updated
  end

  # One representative per group (Full Score > Conductor > alphabetical). Recomputed for
  # the whole catalogue in ONE atomic UPDATE: it promotes each group's winner and demotes
  # any prior winner together, so a crash can never leave a group with zero representatives
  # (a state deduplicate_arrangements would hide from browse/hub). A single statement also
  # means a single short write-lock hold — no multi-statement transaction to block web
  # writes on this single-writer SQLite box.
  def assign_representatives
    Score.connection.update(<<~SQL.squish)
      WITH winners(id) AS (
        SELECT (
          SELECT s2.id FROM scores s2
          WHERE s2.group_key = groups.group_key
            AND s2.deleted_at IS NULL
          ORDER BY
            CASE
              WHEN s2.title LIKE '%Full Score%' THEN 0
              WHEN s2.title LIKE '%Conductor%' THEN 1
              ELSE 2
            END,
            s2.title
          LIMIT 1
        )
        FROM (SELECT DISTINCT group_key FROM scores WHERE group_key IS NOT NULL AND deleted_at IS NULL) groups
      )
      UPDATE scores
      SET is_group_representative = CASE WHEN id IN (SELECT id FROM winners) THEN 1 ELSE NULL END
      WHERE is_group_representative IS NOT NULL OR id IN (SELECT id FROM winners)
    SQL
  end
end
