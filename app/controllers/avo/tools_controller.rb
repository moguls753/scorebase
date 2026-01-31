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

  def analytics
    @page_title = "Analytics Dashboard"
    add_breadcrumb "Analytics"

    @range_days = (params[:days] || 14).to_i.clamp(1, 90)
    @stats = DailyStat.where(date: @range_days.days.ago..Date.current).order(date: :asc)

    @total_visits = @stats.sum(:visits)
    @avg_daily_visits = @stats.any? ? (@total_visits.to_f / @stats.count).round : 0
    @today = DailyStat.find_by(date: Date.current)

    @countries = aggregate_json_field(:countries)
    @referrers = aggregate_json_field(:referrers)
    @paths = aggregate_json_field(:paths)
    @devices = aggregate_json_field(:devices)
    @browsers = aggregate_json_field(:browsers)
    @user_agents = aggregate_json_field(:user_agents)

    # Preload score titles for path display
    score_ids = @paths.keys.filter_map { |p| p[%r{/scores/(\d+)}, 1]&.to_i }.uniq.first(50)
    @score_titles = Score.where(id: score_ids).pluck(:id, :title).to_h
  end

  def smd_stats
    @page_title = "SMD Affiliate Stats"
    add_breadcrumb "SMD Stats"

    @stats = DailyStat.where(date: 14.days.ago..Date.current).order(date: :desc)
    @visits_30d = DailyStat.where(date: 30.days.ago..Date.current).sum(:visits)
    @clicks_30d = DailyStat.where(date: 30.days.ago..Date.current).sum(&:total_smd_clicks)

    # Aggregate clicks by score across all time
    clicks_by_score = DailyStat.pluck(:smd_clicks_by_score).compact.each_with_object(Hash.new(0)) do |day_clicks, totals|
      day_clicks.each { |score_id, count| totals[score_id.to_i] += count }
    end

    # Get top 50 scores with their click counts
    top_score_ids = clicks_by_score.sort_by { |_, count| -count }.first(50).to_h
    scores = Score.where(id: top_score_ids.keys).index_by(&:id)
    @top_clicked_scores = top_score_ids.map { |id, clicks| [scores[id], clicks] }.reject { |s, _| s.nil? }
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
    @stats.pluck(field).compact.each_with_object(Hash.new(0)) do |day_data, totals|
      day_data.each { |key, count| totals[key] += count }
    end.sort_by { |_, v| -v }.to_h
  end
end
