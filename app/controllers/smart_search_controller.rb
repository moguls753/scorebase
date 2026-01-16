class SmartSearchController < ApplicationController
  http_basic_authenticate_with(
    name: Rails.application.credentials.dig(:basic_auth, :user) || "admin",
    password: Rails.application.credentials.dig(:basic_auth, :password),
    if: -> { Rails.env.production? && Rails.application.credentials.dig(:basic_auth, :password).present? }
  )

  def show
    @query = params[:q].to_s.strip

    if @query.blank?
      @rag_result = RagSearch::Result.new({})
      @scores = Score.none
      return
    end

    # Call RAG API for smart recommendations
    @rag_result = RagSearch.smart_search(@query)

    # Load full score objects from database
    if @rag_result.score_ids.any?
      scores_by_id = Score.where(id: @rag_result.score_ids).index_by(&:id)
      # Preserve RAG ranking order
      @scores = @rag_result.score_ids.filter_map { |id| scores_by_id[id] }
    else
      @scores = []
    end
  end
end
