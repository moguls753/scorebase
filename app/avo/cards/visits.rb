class Avo::Cards::Visits < Avo::Cards::MetricCard
  self.id = "visits"
  self.label = "Visits (30 Days)"
  self.cols = 1

  def query
    total = DailyStat.where(date: 30.days.ago..Date.current).sum(:visits)
    result total
  end
end
