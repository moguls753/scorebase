class Avo::Filters::ScoreRagStatusFilter < Avo::Filters::SelectFilter
  self.name = "RAG Status"

  def apply(request, query, value)
    query.where(rag_status: value)
  end

  def options
    # { "Display Name" => "db_value" }
    Score.rag_statuses.keys.index_with(&:titleize).invert
  end
end
