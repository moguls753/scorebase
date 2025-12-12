class ScoresController < ApplicationController
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

    # Forces filter (number of parts)
    @scores = apply_forces_filter(@scores, params[:voicing]) if params[:voicing].present?

    # Voice type filter (choir type)
    @scores = apply_voice_type_filter(@scores, params[:voice_type]) if params[:voice_type].present?

    # Sorting
    @scores = apply_sorting(@scores, params[:sort])

    # Pagination
    @scores = @scores.page(params[:page])

    # Stats for filters
    @total_count = Score.count
    @filtered_count = @scores.total_count
  end

  def show
    @score = Score.find(params[:id])
  end

  def serve_file
    @score = Score.find(params[:id])
    file_type = params[:file_type]

    # Get the file path based on type
    file_path = case file_type
    when 'pdf'
      @score.pdf_path
    when 'mxl'
      @score.mxl_path
    when 'mid'
      @score.mid_path
    else
      nil
    end

    # Validate file path exists and is not N/A
    if file_path.blank? || file_path == 'N/A'
      render plain: "File not available", status: :not_found
      return
    end

    # Handle CPDL scores - redirect to external file URL
    # For CPDL, file_path already contains the full URL
    if @score.cpdl?
      if file_path.start_with?('http')
        redirect_to file_path, allow_other_host: true
        return
      else
        render plain: "CPDL file URL unavailable", status: :not_found
        return
      end
    end

    # Handle PDMX scores - serve from local filesystem
    # Convert relative path to absolute path (PDMX data location)
    absolute_path = File.join(ENV.fetch('PDMX_DATA_PATH', File.expand_path('~/data/pdmx')), file_path.sub(/^\.\//, ''))

    # Check if file exists
    unless File.exist?(absolute_path)
      render plain: "File not found: #{file_path}", status: :not_found
      return
    end

    # Serve the file
    # Use disposition: 'inline' for PDFs (for preview), 'attachment' for downloads
    disposition = params[:download] == 'true' ? 'attachment' : 'inline'

    # Build a nice filename from score title and composer
    nice_filename = "#{@score.title.parameterize}"
    nice_filename += "-#{@score.composer.parameterize}" if @score.composer.present?
    nice_filename += ".#{file_type}"

    send_file absolute_path,
              disposition: disposition,
              type: content_type_for(file_type),
              filename: nice_filename
  end

  private

  def content_type_for(file_type)
    case file_type
    when 'pdf'
      'application/pdf'
    when 'mxl'
      'application/vnd.recordare.musicxml'
    when 'mid'
      'audio/midi'
    else
      'application/octet-stream'
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
      scores
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
end
