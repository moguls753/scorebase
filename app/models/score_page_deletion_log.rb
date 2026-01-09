# frozen_string_literal: true

# Logs all ScorePage deletions via SQLite trigger + Rails callback.
#
# Two sources of logs:
# - 'trigger': SQLite trigger catches ALL deletions (delete_all, CASCADE, raw SQL)
# - 'callback': Rails before_destroy logs with call stack context
#
# If you see 'trigger' entries without matching 'callback' entries,
# the deletion bypassed Rails (delete_all or CASCADE).
# == Schema Information
#
# Table name: score_page_deletion_logs
#
#  id            :integer          not null, primary key
#  context       :text
#  deleted_at    :datetime         not null
#  page_number   :integer          not null
#  source        :string
#  score_id      :integer          not null
#  score_page_id :integer          not null
#
# Indexes
#
#  index_score_page_deletion_logs_on_deleted_at  (deleted_at)
#  index_score_page_deletion_logs_on_score_id    (score_id)
#
class ScorePageDeletionLog < ApplicationRecord
  scope :recent, -> { order(deleted_at: :desc) }
  scope :today, -> { where("deleted_at >= ?", Time.current.beginning_of_day.utc) }
  scope :from_trigger, -> { where(source: "trigger") }
  scope :from_callback, -> { where(source: "callback") }

  def self.summary
    {
      total: count,
      from_trigger: from_trigger.count,
      from_callback: from_callback.count,
      unique_scores_affected: select(:score_id).distinct.count,
      first_deletion: minimum(:deleted_at),
      last_deletion: maximum(:deleted_at),
      today: today.count
    }
  end

  # Log a deletion from Rails callback (with context)
  def self.log_from_callback(score_page, context: nil)
    context ||= caller.reject { |l| l.include?("/gems/") }.first(15).join("\n")

    create!(
      score_page_id: score_page.id,
      score_id: score_page.score_id,
      page_number: score_page.page_number,
      deleted_at: Time.current,
      source: "callback",
      context: context
    )
  end
end
