class SmartSearchFeedback < ApplicationRecord
  belongs_to :smart_search_query

  enum :verdict, { good: "good", bad: "bad" }, validate: true

  validates :ip_hash, presence: true
  validates :ip_hash, uniqueness: { scope: :smart_search_query_id, message: "already voted on this query" }
  validates :comment, length: { maximum: 1000 }, allow_blank: true
end
