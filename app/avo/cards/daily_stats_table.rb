class Avo::Cards::DailyStatsTable < Avo::Cards::PartialCard
  self.id = "daily_stats_table"
  self.label = "Recent Daily Stats"
  self.partial = "avo/cards/daily_stats_table"
  self.cols = 3
  self.rows = 2

  def query
    @stats = DailyStat.where(date: 14.days.ago..Date.current).order(date: :desc)
  end
end
