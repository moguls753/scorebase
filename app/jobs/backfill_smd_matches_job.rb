class BackfillSmdMatchesJob < ApplicationJob
  queue_as :default

  # Idempotent, so a transient SQLite lock can safely retry from scratch
  retry_on ActiveRecord::StatementInvalid, wait: :polynomially_longer, attempts: 3

  def perform
    stats = converge(desired_matches(smd_index))
    logger.info "[BackfillSmdMatches] #{stats}"
    stats
  end

  # Uncapped, pre-suppression desired matches (free_id => [smd_id, ...]) via the exact
  # index and matching #perform writes, so the DRY_RUN rake preview can't drift from it.
  def compute_matches
    desired_matches(smd_index)
  end

  private

  # Batched so the 209k raw rows are never all resident: plucking them in one go
  # cost ~126 MB on top of the index itself, which OOM-killed the 1 GB job container.
  def smd_index
    index = {}
    # Audio products (backing tracks, performance recordings) are not sheet-music
    # editions, so they never belong in "Professional Editions".
    scope = Score.active.where(source: "smd").deduplicate_arrangements
                 .where("smd_category IS NULL OR smd_category NOT LIKE ?", "%Audio%")
    scope.in_batches do |batch|
      SmdMatchFinder.build_index(
        batch.pluck(:id, :title, :composer, :artist, :price_usd, :main_instrument), index
      )
    end
    index
  end

  FREE_COLUMNS = %i[id title composer voicing is_instrumental instruments].freeze

  def desired_matches(index)
    desired = {}
    Score.active.where.not(source: "smd").in_batches do |batch|
      batch.pluck(*FREE_COLUMNS).each do |id, title, composer, voicing, is_instrumental, instruments|
        family = SmdMatchFinder.free_family(voicing, is_instrumental, instruments)
        ids = SmdMatchFinder.matches_for(title, composer, index, free_family: family)
        desired[id] = ids if ids.any?
      end
    end
    desired
  end

  # Diff against stored rows; only changed scores get writes. Changed scores are
  # rewritten delete-then-insert in one transaction — in-place rank updates would
  # trip the unique [score_id, rank] index on swaps. Suppressed rows persist and
  # their targets are never re-added.
  def converge(desired)
    existing = ScoreSmdMatch.pluck(:score_id, :smd_score_id, :rank, :suppressed)
                            .group_by(&:first)
    stats = { matched_scores: 0, created: 0, removed: 0, unchanged: 0 }
    reset_ids = []
    inserts = []

    (desired.keys | existing.keys).each do |score_id|
      rows = existing[score_id] || []
      suppressed_ids = rows.select { |r| r[3] }.map { |r| r[1] }
      current = rows.reject { |r| r[3] }.sort_by { |r| r[2] }.map { |r| r[1] }
      wanted = ((desired[score_id] || []) - suppressed_ids).first(SmdMatchFinder::MAX_MATCHES)

      stats[:matched_scores] += 1 if wanted.any?
      next stats[:unchanged] += 1 if current == wanted

      reset_ids << score_id
      stats[:removed] += current.size
      stats[:created] += wanted.size
      wanted.each_with_index do |smd_id, i|
        inserts << { score_id: score_id, smd_score_id: smd_id, rank: i + 1 }
      end
    end

    if reset_ids.any?
      ScoreSmdMatch.transaction do
        ScoreSmdMatch.where(score_id: reset_ids, suppressed: false).delete_all
        inserts.each_slice(500) { |slice| ScoreSmdMatch.insert_all(slice, record_timestamps: true) }
      end
    end
    stats
  end
end
