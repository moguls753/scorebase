class Avo::Filters::ScoreSourceFilter < Avo::Filters::SelectFilter
  self.name = "Source"

  def apply(request, query, value)
    query.where(source: value)
  end

  def options
    Score::SOURCES.map { |s| [s, s] }.to_h
  end
end
