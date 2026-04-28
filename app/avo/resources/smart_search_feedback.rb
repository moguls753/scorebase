class Avo::Resources::SmartSearchFeedback < Avo::BaseResource
  self.title = :id
  self.includes = [:smart_search_query]

  def fields
    field :id, as: :id
    field :smart_search_query, as: :belongs_to
    field :verdict, as: :badge, options: { good: :success, bad: :warning }
    field :comment, as: :textarea
    field :ip_hash, as: :text, hide_on: :index
    field :created_at, as: :date_time, sortable: true
  end
end
