class Avo::Filters::ScoreStatusFilter < Avo::Filters::SelectFilter
  self.name = "Status"

  def apply(request, query, value)
    case value
    when "active"
      query.where(deleted_at: nil)
    when "deleted"
      query.where.not(deleted_at: nil)
    when "all"
      query
    else
      query
    end
  end

  def options
    {
      "active": "Active",
      "deleted": "Deleted",
      "all": "All"
    }
  end

  def default
    :active
  end
end
