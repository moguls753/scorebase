# == Schema Information
#
# Table name: smart_search_feedbacks
#
#  id                    :integer          not null, primary key
#  comment               :text
#  ip_hash               :string(64)       not null
#  verdict               :string           not null
#  created_at            :datetime         not null
#  smart_search_query_id :integer          not null
#
# Indexes
#
#  idx_one_feedback_per_query_per_visitor                 (smart_search_query_id,ip_hash) UNIQUE
#  index_smart_search_feedbacks_on_smart_search_query_id  (smart_search_query_id)
#
# Foreign Keys
#
#  smart_search_query_id  (smart_search_query_id => smart_search_queries.id) ON DELETE => cascade
#
class SmartSearchFeedback < ApplicationRecord
  belongs_to :smart_search_query

  enum :verdict, { good: "good", bad: "bad" }, validate: true

  validates :ip_hash, presence: true
  validates :ip_hash, uniqueness: { scope: :smart_search_query_id, message: "already voted on this query" }
  validates :comment, length: { maximum: 1000 }, allow_blank: true
end
