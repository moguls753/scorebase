module ScoresHelper
  # Single source of truth for filter parameters
  FILTER_PARAMS = %i[key time voicing voice_type genre period source difficulty language].freeze

  # Count active filters from params
  def active_filters_count
    FILTER_PARAMS.count { |param| params[param].present? }
  end

  # Generate hidden fields for all filter params to preserve state across forms
  def filter_hidden_fields(form)
    safe_join(FILTER_PARAMS.map { |param| form.hidden_field(param, value: params[param]) })
  end
end
