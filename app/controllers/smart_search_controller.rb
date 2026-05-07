class SmartSearchController < ApplicationController
  # before_action :authenticate, if: -> { Rails.env.production? }
  before_action :validate_input_length, only: [:show, :refine]

  def show
    @query = params[:q].to_s.strip
    return render_empty_form if @query.blank?

    @query_record = SmartSearchQuery.recent_initial_for(@query)
    if @query_record
      hydrate_view_from(@query_record)
      return render :show
    end

    case SmartSearchQuota.try_consume!(ip_hash: hashed_ip)
    in :per_ip_limit
      render_per_ip_limit_reached
    in :site_limit
      render_quota_exhausted
    in Date => charged_date
      @query_record = perform_initial_search(charged_date)
      return unless @query_record
      hydrate_view_from(@query_record)
      render :show
    end
  end

  def feedback
    @query_record = SmartSearchQuery.find(params[:query_id])
    @feedback = @query_record.feedbacks.build(
      verdict: params[:verdict],
      comment: params[:comment],
      ip_hash: hashed_ip
    )
    # Treat "already voted" as success — the user's prior vote is what they wanted to express,
    # so the success state matches their intent. Avoids dead-end error after a re-submit.
    if @feedback.save || already_voted?(@feedback)
      render_feedback_success
    else
      render_feedback_invalid
    end
  rescue ActiveRecord::RecordNotUnique
    # Race-condition variant of the validation hit above; same idempotent UX.
    render_feedback_success
  end

  def refine
    @parent = SmartSearchQuery.find(params[:parent_query_id])
    @query = @parent.query
    return render_invalid("Refinements can only build on initial queries.")        unless @parent.initial?
    return render_invalid("This search has already been refined.")                  if @parent.refinements.exists?
    return render_invalid("This result is too old to refine. Run a fresh search.") unless @parent.refinable?

    @refinement = params[:refinement].to_s.strip
    return render_blank_refinement if @refinement.blank?

    charged_date = SmartSearchUsage.try_consume!
    return render_quota_exhausted unless charged_date

    @query_record = perform_refine(@parent, @refinement, charged_date)
    return unless @query_record
    hydrate_view_from(@query_record)
    respond_to do |format|
      format.turbo_stream
      format.html { render :show }
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
      SmartSearchQuota.refund!(charged_date)
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
    SmartSearchQuota.refund!(charged_date)
    Rails.logger.error("perform_initial_search failed: #{e.class} #{e.message}")
    render_rag_error
    nil
  end

  def render_invalid(message)
    flash.now[:alert] = message
    respond_to do |format|
      format.turbo_stream { render :invalid, status: :unprocessable_entity }
      format.html         { render :show,    status: :unprocessable_entity }
      format.json         { render json: { ok: false, error: message }, status: :unprocessable_entity }
    end
  end

  def render_blank_refinement
    respond_to do |format|
      format.turbo_stream { render :refine_blank, status: :unprocessable_entity }
      format.html         { render :show,         status: :unprocessable_entity }
    end
  end

  def perform_refine(parent, refinement, charged_date)
    started = Time.current
    rag_result = RagSearch.smart_refine(
      original_query: parent.query,
      refinement: refinement,
      previous_summary: parent.rag_summary,
      previous_recommendations: parent.rag_recommendations
    )

    unless rag_result.success
      SmartSearchUsage.refund!(charged_date)
      return render_rag_error
    end

    SmartSearchQuery.create!(
      query: refinement,
      query_type: :refinement,
      parent_query_id: parent.id,
      ip_hash: hashed_ip,
      result_count: rag_result.score_ids.size,
      score_ids: rag_result.score_ids,
      rag_summary: rag_result.summary,
      rag_recommendations: rag_result.recommendations,
      response_time_ms: ((Time.current - started) * 1000).to_i,
      locale: I18n.locale.to_s
    )
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    SmartSearchUsage.refund!(charged_date)
    Rails.logger.warn("refinement persist conflict: #{e.message}")
    render_invalid("This search has already been refined.")
    nil
  rescue StandardError => e
    SmartSearchUsage.refund!(charged_date)
    Rails.logger.error("perform_refine failed: #{e.class} #{e.message}")
    render_rag_error
    nil
  end

  def hashed_ip
    @hashed_ip ||= HashedIp.from(client_ip)
  end

  def already_voted?(feedback_record)
    feedback_record.errors[:ip_hash].any? { |msg| msg.include?("already voted") }
  end

  def render_feedback_success
    respond_to do |format|
      format.turbo_stream { render :feedback }
      format.json { render json: { ok: true }, status: :ok }
      format.html { redirect_back fallback_location: smart_search_path }
    end
  end

  def render_feedback_invalid
    respond_to do |format|
      format.turbo_stream { render :feedback_invalid, status: :unprocessable_entity }
      format.json { render json: { ok: false, errors: @feedback.errors.full_messages }, status: :unprocessable_entity }
      format.html { head :unprocessable_entity }
    end
  end
end
