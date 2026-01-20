class Avo::ToolsController < Avo::ApplicationController
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
