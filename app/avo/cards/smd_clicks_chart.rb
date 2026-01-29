class Avo::Cards::SmdClicksChart < Avo::Cards::PartialCard
  self.id = "smd_clicks_chart"
  self.label = "SMD Clicks vs Visits"
  self.partial = "avo/cards/smd_clicks_chart"
  self.cols = 3
  self.rows = 2
end
