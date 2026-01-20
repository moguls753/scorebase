class Avo::Filters::ScoreStatusFilter < Avo::Filters::SelectFilter
  self.name = "Status"
  self.default = -> { "active" }

  def apply(request, query, value)
    # Remove existing deleted_at condition from index_query before applying filter
    case value
    when "active"
      query.unscope(where: :deleted_at).where(deleted_at: nil)
    when "deleted"
      query.unscope(where: :deleted_at).where.not(deleted_at: nil)
    when "all"
      query.unscope(where: :deleted_at)
    else
      query
    end
  end

  def options
    {
      "Active" => "active",
      "Deleted" => "deleted",
      "All" => "all"
    }
  end
end
