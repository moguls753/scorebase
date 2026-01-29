class Avo::Resources::DailyStat < Avo::BaseResource
  self.title = :date
  self.includes = []
  self.default_view_type = :table

  def fields
    field :id, as: :id
    field :date, as: :date, sortable: true
    field :visits, as: :number, sortable: true
    field :smd_clicks, as: :number, name: "SMD Clicks" do
      record.total_smd_clicks
    end
    field :unique_scores_clicked, as: :number, name: "Scores" do
      (record.smd_clicks_by_score || {}).keys.count
    end
    field :created_at, as: :date_time, sortable: true, hide_on: [:index]
  end
end
