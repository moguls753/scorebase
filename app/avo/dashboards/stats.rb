class Avo::Dashboards::Stats < Avo::Dashboards::BaseDashboard
  self.id = "stats"
  self.name = "Stats"
  self.description = "Site traffic and SMD affiliate tracking"
  self.grid_cols = 3

  def cards
    card Avo::Cards::SmdClicks
    card Avo::Cards::SmdClicksChart
  end
end
