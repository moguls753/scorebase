class Avo::Resources::SmartSearchQuery < Avo::BaseResource
  self.title = :query
  self.includes = [:feedbacks, :parent_query, :refinements]
  self.search = { query: -> { query.where("query LIKE ?", "%#{q}%") } }

  def fields
    field :id, as: :id
    field :query, as: :text
    field :query_type, as: :select, options: { initial: "initial", refinement: "refinement" }
    field :parent_query, as: :belongs_to, hide_on: :index
    field :ip_hash, as: :text, hide_on: :index
    field :result_count, as: :number
    field :score_ids, as: :code, hide_on: :index, language: "json"
    field :rag_summary, as: :textarea, hide_on: :index
    field :rag_recommendations, as: :code, hide_on: :index, language: "json"
    field :response_time_ms, as: :number
    field :error, as: :textarea, hide_on: :index
    field :locale, as: :text
    field :created_at, as: :date_time, sortable: true
    field :feedbacks, as: :has_many
    field :refinements, as: :has_many
  end
end
