class SmartSearchController < ApplicationController
  before_action :authenticate, if: -> { Rails.env.production? }

  def show
    @query = params[:q].to_s.strip

    if @query.blank?
      @rag_result = RagSearch::Result.new({})
      @scores = Score.none
      return
    end

    # Call RAG API for smart recommendations
    @rag_result = RagSearch.smart_search(@query)

    # Load full score objects from database with eager loading for thumbnails
    if @rag_result.score_ids.any?
      scores_by_id = Score
        .where(id: @rag_result.score_ids)
        .with_attached_thumbnail_image
        .index_by(&:id)
      # Preserve RAG ranking order
      @scores = @rag_result.score_ids.filter_map { |id| scores_by_id[id] }
    else
      @scores = []
    end
  end

  private

  def authenticate
    credentials = Rails.application.credentials
    return unless credentials.dig(:basic_auth, :password).present?

    authenticate_or_request_with_http_basic do |user, password|
      ActiveSupport::SecurityUtils.secure_compare(user, credentials.dig(:basic_auth, :user) || "admin") &
        ActiveSupport::SecurityUtils.secure_compare(password, credentials.dig(:basic_auth, :password))
    end
  end
end
