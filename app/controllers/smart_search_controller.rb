class SmartSearchController < ApplicationController
  PER_IP_DAILY_LIMIT = 5

  # Comment this line out when going public, uncomment to revert.
  before_action :authenticate, if: -> { Rails.env.production? }
  before_action :validate_input_length, only: [:show] # Task 12: add :refine

  def show
    @query = params[:q].to_s.strip
    return render_empty_form if @query.blank?

    @query_record = SmartSearchQuery.recent_initial_for(@query)
    if @query_record
      hydrate_view_from(@query_record)
      return render :show
    end

    return render_per_ip_limit_reached if per_ip_limit_reached?

    charged_date = SmartSearchUsage.try_consume!
    return render_quota_exhausted unless charged_date

    @query_record = perform_initial_search(charged_date)
    return unless @query_record
    hydrate_view_from(@query_record)
    render :show
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

  def validate_input_length
    too_long_q       = params[:q].to_s.length          > SmartSearchQuery::MAX_QUERY_LENGTH
    too_long_refine  = params[:refinement].to_s.length > SmartSearchQuery::MAX_REFINEMENT_LENGTH
    return unless too_long_q || too_long_refine

    flash.now[:alert] = "Your input is too long. Please shorten it."
    respond_to do |format|
      format.turbo_stream { render :input_too_long, status: :unprocessable_entity }
      format.html         { render :show,           status: :unprocessable_entity }
    end
  end

  def render_empty_form
    @rag_result = RagSearch::Result.new({})
    @scores = Score.none
    render :show
  end

  def render_quota_exhausted
    @rag_result ||= RagSearch::Result.new({})
    @scores ||= Score.none
    respond_to do |format|
      format.turbo_stream { render :quota_exhausted, status: :too_many_requests }
      format.html         { render :quota_exhausted, status: :too_many_requests }
      format.json         { render json: { ok: false, error: "quota_exhausted" }, status: :too_many_requests }
    end
  end

  def per_ip_limit_reached?
    SmartSearchQuery.recent_ip_count(hashed_ip) >= PER_IP_DAILY_LIMIT
  end

  def render_per_ip_limit_reached
    @rag_result ||= RagSearch::Result.new({})
    @scores ||= Score.none
    respond_to do |format|
      format.turbo_stream { render :per_ip_limit_reached, status: :too_many_requests }
      format.html         { render :per_ip_limit_reached, status: :too_many_requests }
      format.json         { render json: { ok: false, error: "per_ip_limit" }, status: :too_many_requests }
    end
  end

  def render_rag_error
    flash.now[:alert] = "Smart search is temporarily unavailable. Please try again in a moment."
    @rag_result ||= RagSearch::Result.new({})
    @scores ||= Score.none
    @query_record ||= nil
    respond_to do |format|
      format.turbo_stream { render :rag_error, status: :service_unavailable }
      format.html         { render :show,      status: :service_unavailable }
      format.json         { render json: { ok: false, error: "rag_unavailable" }, status: :service_unavailable }
    end
    nil
  end

  def hydrate_view_from(query_record)
    @rag_result = RagSearch::Result.from_query_record(query_record)
    scores_by_id = Score.active.where(id: query_record.score_ids).index_by(&:id)
    @scores = query_record.score_ids.filter_map { |id| scores_by_id[id] }
  end

  def perform_initial_search(charged_date)
    started = Time.current
    rag_result = RagSearch.smart_search(@query)

    unless rag_result.success
      SmartSearchUsage.refund!(charged_date)
      return render_rag_error
    end

    SmartSearchQuery.create!(
      query: @query,
      query_type: :initial,
      ip_hash: hashed_ip,
      result_count: rag_result.score_ids.size,
      score_ids: rag_result.score_ids,
      rag_summary: rag_result.summary,
      rag_recommendations: rag_result.recommendations,
      response_time_ms: ((Time.current - started) * 1000).to_i,
      locale: I18n.locale.to_s
    )
  rescue StandardError => e
    SmartSearchUsage.refund!(charged_date)
    Rails.logger.error("perform_initial_search failed: #{e.class} #{e.message}")
    render_rag_error
    nil
  end

  def hashed_ip
    salt = Digest::SHA256.hexdigest("smart_search_ip|#{Rails.application.secret_key_base}")
    client_ip = request.headers["CF-Connecting-IP"].presence || request.remote_ip
    Digest::SHA256.hexdigest("#{salt}|#{client_ip}")
  end
end
