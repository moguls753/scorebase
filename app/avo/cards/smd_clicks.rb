class Avo::Cards::SmdClicks < Avo::Cards::MetricCard
  self.id = "smd_clicks"
  self.label = "SMD Clicks (30 Days)"
  self.cols = 1

  def query
    total = DailyStat.where(date: 30.days.ago..Date.current).sum(&:total_smd_clicks)
    result total
  end
end
