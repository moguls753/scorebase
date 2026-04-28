class Avo::Resources::SmartSearchUsage < Avo::BaseResource
  self.title = :date
  self.includes = []
  self.search = { query: -> { query.where("CAST(date AS TEXT) LIKE ?", "%#{q}%") } }

  def fields
    field :id, as: :id
    field :date, as: :date, sortable: true
    field :count, as: :number, sortable: true
    field :created_at, as: :date_time, hide_on: [:edit, :new]
    field :updated_at, as: :date_time, hide_on: [:edit, :new]
  end
end
