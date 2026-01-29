class Avo::ToolsController < Avo::ApplicationController
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
end
