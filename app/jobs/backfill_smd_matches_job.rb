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
    Score.active.free.in_batches do |batch|
      batch.pluck(*FREE_COLUMNS).each do |id, title, composer, voicing, is_instrumental, instruments|
        family = SmdMatchFinder.free_family(voicing, is_instrumental, instruments)
        ids = SmdMatchFinder.matches_for(title, composer, index, free_family: family)
        desired[id] = ids if ids.any?
      end
    end
    desired
  end

  def converge(desired)
    PartnerMatchConverge.new(model: ScoreSmdMatch, partner_key: :smd_score_id,
                             max_matches: SmdMatchFinder::MAX_MATCHES).call(desired)
  end
end
