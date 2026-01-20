class Avo::Filters::ScoreStatusFilter < Avo::Filters::SelectFilter
  self.name = "Status"
  self.default = -> { "active" }

  def apply(request, query, value)
    case value
    when "active"
      query.where(deleted_at: nil)
    when "deleted"
      query.where.not(deleted_at: nil)
    when "all"
      query # No filter - show all records
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
