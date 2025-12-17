module ScoresHelper
  # Count active filters from params
  def active_filters_count
    [
      params[:key],
      params[:time],
      params[:voicing],
      params[:voice_type],
      params[:genre],
      params[:period],
      params[:source],
      params[:difficulty],
      params[:language]
    ].compact.reject(&:blank?).count
  end
end
