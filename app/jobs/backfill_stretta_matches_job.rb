# frozen_string_literal: true

# Converges score_stretta_matches, the free -> Stretta cross-links.
# Same delete-then-insert shape as BackfillSmdMatchesJob; see there for why the
# rewrite is per-score rather than in place.
class BackfillStrettaMatchesJob < ApplicationJob
  queue_as :default

  retry_on ActiveRecord::StatementInvalid, wait: :polynomially_longer, attempts: 3

  # Audio is never a buy for a browsing user, so it never enters the index at all —
  # ranking it down would still let it win a group with nothing else in it.
  EXCLUDED_RANKS = [ 90 ].freeze
  FREE_COLUMNS = %i[id title composer voicing is_instrumental instruments].freeze

  def perform
    stats = converge(desired_matches(stretta_index))
    logger.info "[BackfillStrettaMatches] #{stats}"
    stats
  end

  private

  # Batched: the equivalent SMD index at 209k rows OOM-killed the 1 GB container
  # when plucked in one go, and this catalogue is several times larger.
  def stretta_index
    index = {}
    scope = Score.active.where(source: "stretta").not_duplicate.deduplicate_arrangements
                 .where.not(group_rank: EXCLUDED_RANKS)
    scope.in_batches do |batch|
      StrettaMatchFinder.build_index(
        batch.pluck(:id, :title, :composer, :price_eur, :instruments, :group_rank), index
      )
    end
    index
  end

  def desired_matches(index)
    desired = {}
    Score.active.free.in_batches do |batch|
      batch.pluck(*FREE_COLUMNS).each do |id, title, composer, voicing, is_instrumental, instruments|
        family = SmdMatchFinder.free_family(voicing, is_instrumental, instruments)
        ids = StrettaMatchFinder.matches_for(title, composer, index, free_family: family)
        desired[id] = ids if ids.any?
      end
    end
    desired
  end

  def converge(desired)
    PartnerMatchConverge.new(model: ScoreStrettaMatch, partner_key: :stretta_score_id,
                             max_matches: StrettaMatchFinder::MAX_MATCHES).call(desired)
  end
end
