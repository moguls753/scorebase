# frozen_string_literal: true

# Brings a free-score -> partner-edition match table in line with a freshly
# computed set of desired matches.
#
# Shared by both partners because the tricky parts are identical and must stay
# identical: only changed scores are written; a changed score is rewritten
# delete-then-insert in one transaction, since in-place rank updates would trip
# the unique [score_id, rank] index on a swap; and suppressed rows survive every
# run so a false positive killed by hand stays dead.
class PartnerMatchConverge
  INSERT_SLICE = 500

  def initialize(model:, partner_key:, max_matches:)
    @model = model
    @partner_key = partner_key
    @max_matches = max_matches
  end

  # desired: { free_score_id => [partner_score_id, ...] }, uncapped and pre-suppression.
  def call(desired)
    existing = @model.pluck(:score_id, @partner_key, :rank, :suppressed).group_by(&:first)
    stats = { matched_scores: 0, created: 0, removed: 0, unchanged: 0 }
    reset_ids = []
    inserts = []

    (desired.keys | existing.keys).each do |score_id|
      rows = existing[score_id] || []
      wanted = wanted_for(desired[score_id], rows)
      current = current_for(rows)

      stats[:matched_scores] += 1 if wanted.any?
      if current == wanted
        stats[:unchanged] += 1
        next
      end

      reset_ids << score_id
      stats[:removed] += current.size
      stats[:created] += wanted.size
      wanted.each_with_index { |id, i| inserts << { score_id: score_id, @partner_key => id, rank: i + 1 } }
    end

    write(reset_ids, inserts)
    stats
  end

  private

  def wanted_for(desired_ids, rows)
    suppressed = rows.filter_map { |_score_id, partner_id, _rank, suppressed| partner_id if suppressed }
    ((desired_ids || []) - suppressed).first(@max_matches)
  end

  def current_for(rows)
    rows.reject { |_score_id, _partner_id, _rank, suppressed| suppressed }
        .sort_by { |_score_id, _partner_id, rank, _suppressed| rank }
        .map { |_score_id, partner_id, _rank, _suppressed| partner_id }
  end

  def write(reset_ids, inserts)
    return if reset_ids.empty?

    @model.transaction do
      @model.where(score_id: reset_ids, suppressed: false).delete_all
      inserts.each_slice(INSERT_SLICE) { |slice| @model.insert_all(slice, record_timestamps: true) }
    end
  end
end
