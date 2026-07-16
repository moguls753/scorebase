class BackfillGroupKeysJob < ApplicationJob
  queue_as :default

  # Idempotent, so a transient SQLite lock can safely retry from scratch
  retry_on ActiveRecord::StatementInvalid, wait: :polynomially_longer, attempts: 3

  def perform
    scope = Score.where(source: "smd")

    stats = {
      part_keys: assign_part_keys(scope),
      bundle_keys: assign_bundle_keys(scope),
      parent_keys: assign_parent_keys(scope),
      representatives: assign_representatives
    }
    logger.info "[BackfillGroupKeys] #{stats}"
    stats
  end

  private

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

  # Must run after assign_part_keys: bundles only match once sibling parts carry the key
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

  # Complete-set listings (bare title, shared product code). Absorbed only as the
  # group's unique bare candidate with a category matching the group's parts —
  # a shared HL folio code alone also links distinct SKUs (choir vocal scores,
  # audio tracks) that must stay visible as their own cards.
  def assign_parent_keys(scope)
    candidates = Hash.new { |hash, key| hash[key] = [] }
    scope.active.where(group_key: nil).where("title NOT LIKE '% - %'").find_each do |score|
      key = Score.derive_parent_group_key(score.title, score.thumbnail_url)
      candidates[key] << score if key
    end

    updated = 0
    candidates.each do |key, scores|
      next unless scores.one?

      parent = scores.first
      next unless parent_category_matches_group?(parent, key)

      parent.update_column(:group_key, key)
      updated += 1
    end
    updated
  end

  def parent_category_matches_group?(parent, key)
    category = parent.smd_category
    return false if category.blank? || category.match?(/audio/i)

    Score.active.where(group_key: key).where.not(id: parent.id)
         .distinct.pluck(:smd_category).include?(category)
  end

  # One atomic UPDATE: promotes each group's winner and demotes prior winners
  # together. A crash mid-job can leave stale flags, but every arrangement keeps
  # one visible card throughout (cleared keys fall back to the ungrouped branch)
  # and the retry/nightly rerun converges.
  def assign_representatives
    Score.connection.update(<<~SQL.squish)
      WITH winners(id) AS (
        SELECT (
          SELECT s2.id FROM scores s2
          WHERE s2.group_key = groups.group_key
            AND s2.deleted_at IS NULL
          ORDER BY #{Score::GROUP_REPRESENTATIVE_ORDER_SQL}
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
