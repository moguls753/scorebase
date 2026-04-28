class SmartSearchQuery < ApplicationRecord
  RECENT_QUERY_TTL = 6.hours
  MAX_QUERY_LENGTH = 500
  MAX_REFINEMENT_LENGTH = 300
  MAX_SUMMARY_LENGTH = 1000
  MAX_EXPLANATION_LENGTH = 500
  MAX_RECOMMENDATIONS = 5

  enum :query_type, { initial: "initial", refinement: "refinement" }

  belongs_to :parent_query, class_name: "SmartSearchQuery", optional: true
  has_many   :refinements, class_name: "SmartSearchQuery", foreign_key: :parent_query_id, dependent: :nullify
  has_many   :feedbacks,   class_name: "SmartSearchFeedback", dependent: :destroy

  serialize :score_ids,           coder: JSON
  serialize :rag_recommendations, coder: JSON

  validates :query,           presence: true, length: { maximum: MAX_QUERY_LENGTH }
  validates :parent_query_id, presence: true, if: :refinement?
  validate  :parent_must_be_initial,    if: :refinement?
  validate  :parent_must_be_unrefined,  if: :refinement?, on: :create

  before_save :truncate_rag_fields

  def self.recent_initial_for(query_text)
    initial
      .where("LOWER(TRIM(query)) = ?", query_text.to_s.strip.downcase)
      .where("created_at > ?", RECENT_QUERY_TTL.ago)
      .where(error: nil)
      .order(created_at: :desc)
      .first
  end

  # Failed queries (error: not nil) don't count against the user's allowance —
  # a flaky RAG outage shouldn't burn it.
  def self.recent_ip_count(ip_hash, since: 24.hours.ago)
    where(ip_hash: ip_hash)
      .where("created_at > ?", since)
      .where(error: nil)
      .count
  end

  def refinable?
    initial? &&
      rag_summary.present? &&
      rag_recommendations.is_a?(Array) &&
      rag_recommendations.any? &&
      refinements.none?
  end

  private

  def parent_must_be_initial
    errors.add(:parent_query, "must be an initial query") unless parent_query&.initial?
  end

  def parent_must_be_unrefined
    return unless parent_query
    if parent_query.refinements.where.not(id: id).exists?
      errors.add(:parent_query, "has already been refined")
    end
  end

  def truncate_rag_fields
    self.rag_summary = rag_summary.to_s.first(MAX_SUMMARY_LENGTH) if rag_summary.present?
    if rag_recommendations.is_a?(Array)
      self.rag_recommendations = rag_recommendations.first(MAX_RECOMMENDATIONS).map do |rec|
        rec.merge("explanation" => rec["explanation"].to_s.first(MAX_EXPLANATION_LENGTH))
      end
    end
  end
end
