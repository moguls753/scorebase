class Avo::ToolsController < Avo::ApplicationController
  helper AvoToolsHelper

  COUNTRY_NAMES = {
    "DE" => "Germany", "US" => "United States", "GB" => "United Kingdom",
    "FR" => "France", "ES" => "Spain", "IT" => "Italy", "NL" => "Netherlands",
    "AT" => "Austria", "CH" => "Switzerland", "BE" => "Belgium", "PL" => "Poland",
    "CA" => "Canada", "AU" => "Australia", "BR" => "Brazil", "MX" => "Mexico",
    "JP" => "Japan", "KR" => "South Korea", "CN" => "China", "IN" => "India",
    "RU" => "Russia", "SE" => "Sweden", "NO" => "Norway", "DK" => "Denmark",
    "FI" => "Finland", "PT" => "Portugal", "CZ" => "Czech Republic", "HU" => "Hungary"
  }.freeze

  # Both dashboards default to the same window so their headline numbers stay comparable.
  DEFAULT_WINDOW_DAYS = 30
  MAX_WINDOW_DAYS     = 180

  def analytics
    @page_title = "Analytics Dashboard"
    add_breadcrumb "Analytics"

    @range_days = (params[:days] || DEFAULT_WINDOW_DAYS).to_i.clamp(1, MAX_WINDOW_DAYS)
    @stats      = DailyStat.in_window(@range_days).order(date: :asc)
    @summary    = @stats.summary
    @today      = DailyStat.find_by(date: Date.current)

    @countries = aggregate_json_field(:countries)
    @referrers = aggregate_json_field(:referrers)
    @paths     = aggregate_json_field(:paths)
    @devices   = aggregate_json_field(:devices)

    score_ids = @paths.keys.filter_map { |p| p[%r{/scores/(\d+)}, 1]&.to_i }.uniq.first(50)
    @score_titles = Score.where(id: score_ids).pluck(:id, :title).to_h
  end

  def smd_stats
    @page_title = "SMD Affiliate Stats"
    add_breadcrumb "SMD Stats"

    @range_days = DEFAULT_WINDOW_DAYS
    @stats      = DailyStat.in_window(@range_days).order(date: :desc)
    @summary    = @stats.summary

    clicks_by_score = @stats.measured.pluck(:smd_clicks_by_score).compact.each_with_object(Hash.new(0)) do |day_clicks, totals|
      day_clicks.each { |score_id, count| totals[score_id.to_i] += count }
    end

    top_score_ids = clicks_by_score.sort_by { |_, count| -count }.first(20).to_h
    scores = Score.where(id: top_score_ids.keys).index_by(&:id)
    @top_clicked_scores = top_score_ids.filter_map { |id, clicks| [scores[id], clicks] if scores[id] }
  end

  def rag_pipeline
    @page_title = "RAG Pipeline Status"
    add_breadcrumb "RAG Pipeline"

    # RAG service health
    @rag_available = RagSearch.available?

    # Score counts by RAG status
    @status_counts = Score.group(:rag_status).count

    # Total scores
    @total_scores = Score.count

    # Recently indexed
    @recently_indexed = Score.where.not(indexed_at: nil)
                             .order(indexed_at: :desc)
                             .limit(10)

    # Failed scores (need investigation)
    @failed_scores = Score.rag_failed.limit(20)

    # Extraction stats
    @extraction_counts = Score.group(:extraction_status).count

    # Waitlist count
    @waitlist_count = WaitlistSignup.count
  end

  private

  def aggregate_json_field(field)
    @stats.measured.pluck(field).compact.each_with_object(Hash.new(0)) do |day_data, totals|
      day_data.each { |key, count| totals[key] += count }
    end.sort_by { |_, v| -v }.to_h
  end
end
