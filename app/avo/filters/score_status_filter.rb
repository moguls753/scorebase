class Avo::Filters::ScoreStatusFilter < Avo::Filters::SelectFilter
  self.name = "Status"
  self.default = -> { "active" }

  def apply(request, query, value)
    # Use unscope(:where) with deleted_at to preserve other filters
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
