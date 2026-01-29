class Avo::Resources::DailyStat < Avo::BaseResource
  self.title = :date
  self.includes = []
  self.default_view_type = :table

  def fields
    field :id, as: :id
    field :date, as: :date, sortable: true
    field :visits, as: :number, sortable: true
    field :smd_clicks, as: :number, sortable: true, name: "SMD Clicks"
    field :smd_click_rate, as: :text, name: "Click Rate" do
      if record.visits.to_i > 0 && record.smd_clicks.to_i > 0
        rate = (record.smd_clicks.to_f / record.visits * 100).round(2)
        "#{rate}%"
      else
        "-"
      end
    end
    field :created_at, as: :date_time, sortable: true, hide_on: [:index]
  end
end
