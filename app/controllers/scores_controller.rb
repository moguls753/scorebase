class ScoresController < ApplicationController
  allow_unauthenticated_access except: [:smart_search]
  before_action :require_authentication, only: [:smart_search]
  before_action :check_search_limit, only: [:smart_search]

  def smart_search
    @query = params[:q].to_s.strip
    @searches_remaining = Current.user.searches_remaining

    if @query.blank?
      @rag_result = RagSearch::Result.new({})
      @scores = Score.none
      return
    end

    # Increment count before search (so failed API calls still count)
    Current.user.use_smart_search!
    @searches_remaining = Current.user.searches_remaining

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

  def index
    @scores = Score.all

    # Search
    if params[:q].present?
      @scores = @scores.search(params[:q])
    end

    # Filters
    @scores = @scores.by_source(params[:source]) if params[:source].present?
    @scores = @scores.by_key_signature(params[:key]) if params[:key].present?
    @scores = @scores.by_time_signature(params[:time]) if params[:time].present?
    @scores = @scores.by_genre(params[:genre]) if params[:genre].present?
    @scores = @scores.by_period(params[:period]) if params[:period].present?
    @scores = @scores.by_complexity(params[:difficulty]) if params[:difficulty].present?
    @scores = @scores.where(language: params[:language]) if params[:language].present?

    # Forces filter (number of parts)
    @scores = apply_forces_filter(@scores, params[:voicing]) if params[:voicing].present?

    # Voice type filter (choir type)
    @scores = apply_voice_type_filter(@scores, params[:voice_type]) if params[:voice_type].present?

    # Sorting
    @scores = apply_sorting(@scores, params[:sort])

    # Stats for filters (count before pagination)
    @total_count = Score.count
    @filtered_count = @scores.count

    # Pagination (without_count skips redundant COUNT query)
    @scores = @scores.with_attached_thumbnail_image.page(params[:page]).without_count
  end

  def show
    @score = Score
      .with_attached_thumbnail_image
      .includes(score_pages: { image_attachment: :blob })
      .find(params[:id])
    @score.increment!(:views) unless bot?
  end

  # NOTE: Hybrid file serving - three approaches by design:
  # 1. IMSLP/CPDL: Active Storage (R2) - CDN speed + cheaper than Hetzner disk
  # 2. PDMX: Local disk (/opt/pdmx) - 16GB already there, no migration needed
  # 3. OpenScore: Local disk (/opt/openscore-pdfs for PDFs, corpus dir for MXLs)
  # Thumbnails always go to R2 for CDN benefit on grid views.
  def serve_file
    @score = Score.find(params[:id])
    file_type = params[:file_type]
    disposition = params[:download] == "true" ? "attachment" : "inline"
    nice_filename = nice_filename_for(file_type)

    # 1. Active Storage (R2) - synced IMSLP/CPDL files
    attachment = attachment_for(file_type)
    if attachment&.attached?
      redirect_to rails_blob_path(attachment, disposition: disposition, filename: nice_filename)
      return
    end

    file_path = case file_type
    when "pdf" then @score.pdf_path
    when "mxl" then @score.mxl_path
    when "mid" then @score.mid_path
    end

    if file_path.blank? || file_path == "N/A"
      render plain: "File not available", status: :not_found
      return
    end

    # 2. External fallback - redirect to source if not synced yet
    if @score.external?
      external_url = case file_type
      when "pdf" then @score.pdf_url
      when "mxl" then @score.mxl_url
      when "mid" then @score.mid_url
      end

      if external_url.present?
        redirect_to external_url, allow_other_host: true
      else
        render plain: "External file URL unavailable", status: :not_found
      end
      return
    end

    # 3. Local disk - PDMX and OpenScore files
    absolute_path, base_path = local_file_path_for(@score, file_type, file_path)

    unless absolute_path && base_path
      render plain: "Unknown source", status: :not_found
      return
    end

    # Prevent path traversal attacks
    unless absolute_path.start_with?(File.expand_path(base_path))
      render plain: "Invalid file path", status: :forbidden
      return
    end

    unless File.exist?(absolute_path)
      render plain: "File not found", status: :not_found
      return
    end

    send_file absolute_path,
              disposition: disposition,
              type: content_type_for(file_type),
              filename: nice_filename
  end

  private

  def attachment_for(file_type)
    case file_type
    when "pdf" then @score.pdf_file
    end
  end

  def nice_filename_for(file_type)
    name = @score.title.parameterize.presence || "score"
    name += "-#{@score.composer.parameterize}" if @score.composer.present?
    "#{name}.#{file_type}"
  end

  def content_type_for(file_type)
    case file_type
    when "pdf"
      "application/pdf"
    when "mxl"
      "application/vnd.recordare.musicxml"
    when "mid"
      "audio/midi"
    else
      "application/octet-stream"
    end
  end

  # Returns [absolute_path, base_path] for local file serving
  # OpenScore has different paths for PDFs (generated) vs MXLs (corpus)
  def local_file_path_for(score, file_type, file_path)
    if score.pdmx?
      base_path = Rails.application.config.x.pdmx_path
      absolute_path = base_path.join(file_path.delete_prefix("./")).to_s
      [absolute_path, base_path.to_s]
    elsif score.openscore?
      if file_type == "pdf"
        base_path = Rails.application.config.x.openscore_pdfs_path
        absolute_path = base_path.join(file_path).to_s
        [absolute_path, base_path.to_s]
      elsif file_type == "mxl"
        # MXLs are in the corpus directory - use corpus root for traversal check
        base_path = score.source == "openscore-lieder" ? OpenscoreImporter.root_path : OpenscoreQuartetsImporter.root_path
        absolute_path = base_path.join(file_path.delete_prefix("./")).to_s
        [absolute_path, base_path.to_s]
      else
        [nil, nil]
      end
    else
      [nil, nil]
    end
  end

  def apply_forces_filter(scores, forces)
    case forces
    when "solo"
      scores.solo
    when "duet"
      scores.duet
    when "trio"
      scores.trio
    when "quartet"
      scores.quartet
    when "ensemble"
      scores.ensemble
    else
      # Handle specific voicings (SATB, SSAA, etc.) from bot traffic
      if forces.match?(/\A[SATB]{1,12}\z/i)
        scores.where(voicing: forces.upcase)
      else
        scores.none # Invalid voicing param = no results (fast)
      end
    end
  end

  def apply_voice_type_filter(scores, voice_type)
    case voice_type
    when "mixed"
      scores.mixed_voices
    when "treble"
      scores.treble_voices
    when "mens"
      scores.mens_voices
    when "unison"
      scores.unison_voices
    else
      scores
    end
  end

  def apply_sorting(scores, sort)
    case sort
    when "popularity"
      scores.order_by_popularity
    when "rating"
      scores.order_by_rating
    when "newest"
      scores.order_by_newest
    when "title"
      scores.order_by_title
    when "composer"
      scores.order_by_composer
    else
      scores.order_by_popularity # Default
    end
  end

  def check_search_limit
    Current.user.ensure_monthly_reset!
    unless Current.user.can_smart_search?
      render :search_limit_reached
    end
  end
end
