class Avo::Resources::WaitlistSignup < Avo::BaseResource
  self.title = :email
  self.search = {
    query: -> { query.where("email LIKE ?", "%#{q}%") }
  }

  def fields
    field :id, as: :id
    field :email, as: :text, sortable: true
    field :locale, as: :select, options: { "en" => "English", "de" => "Deutsch" }, sortable: true
    field :created_at, as: :date_time, sortable: true
  end
end
