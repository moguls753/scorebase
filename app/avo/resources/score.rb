class Avo::Resources::Score < Avo::BaseResource
  self.title = :title
  self.search = {
    query: -> {
      if q.match?(/^\d+$/)
        query.where(id: q.to_i)
      else
        query.where("title LIKE ? OR composer LIKE ?", "%#{q}%", "%#{q}%")
      end
    }
  }

  def fields
    # Index view: show only essential columns
    field :id, as: :id, link_to_record: true
    field :view_on_site, as: :text, only_on: :show do
      link_to "Open on ScoreBase →", "/scores/#{record.id}", target: "_blank", class: "text-blue-600 hover:underline"
    end
    field :title, as: :text, sortable: true, link_to_record: true
    field :composer, as: :text, sortable: true
    field :source, as: :select, options: Score::SOURCES.map { |s| [s, s] }.to_h, sortable: true
    field :instruments, as: :text, hide_on: :index
    field :voicing, as: :text, sortable: true
    field :pedagogical_grade, as: :text, sortable: true, name: "Grade"
    field :rag_status, as: :select, enum: ::Score.rag_statuses, sortable: true
    field :views, as: :number, sortable: true

    # Basic info (show/edit only)
    field :description, as: :textarea, hide_on: :index
    field :genre, as: :text, hide_on: :index
    field :period, as: :text, hide_on: :index
    field :language, as: :text, hide_on: :index
    field :editor, as: :text, hide_on: :index
    field :license, as: :text, hide_on: :index
    field :tags, as: :textarea, hide_on: :index

    # Music details
    field :key_signature, as: :text, hide_on: :index
    field :time_signature, as: :text, hide_on: :index
    field :num_parts, as: :number, hide_on: :index
    field :tempo_bpm, as: :number, hide_on: :index
    field :tempo_marking, as: :text, hide_on: :index
    field :duration_seconds, as: :number, hide_on: :index
    field :measure_count, as: :number, hide_on: :index
    field :page_count, as: :number, hide_on: :index

    # Vocal/Instrument details
    field :has_vocal, as: :boolean, hide_on: :index
    field :highest_pitch, as: :text, hide_on: :index
    field :lowest_pitch, as: :text, hide_on: :index
    field :lyrics, as: :textarea, hide_on: :index

    # Difficulty
    field :pedagogical_grade_de, as: :text, hide_on: :index, name: "Grade (DE)"
    field :computed_difficulty, as: :number, hide_on: :index
    field :complexity, as: :number, hide_on: :index
    field :grade_status, as: :select, enum: ::Score.grade_statuses, hide_on: :index
    field :grade_source, as: :text, hide_on: :index

    # Normalization statuses
    field :composer_status, as: :select, enum: ::Score.composer_statuses, hide_on: :index
    field :genre_status, as: :select, enum: ::Score.genre_statuses, hide_on: :index
    field :period_status, as: :select, enum: ::Score.period_statuses, hide_on: :index
    field :instruments_status, as: :select, enum: ::Score.instruments_statuses, hide_on: :index
    field :voicing_status, as: :select, enum: ::Score.voicing_statuses, hide_on: :index
    field :has_vocal_status, as: :select, enum: ::Score.has_vocal_statuses, hide_on: :index

    # Extraction
    field :extraction_status, as: :select, enum: ::Score.extraction_statuses, hide_on: :index
    field :extraction_error, as: :textarea, hide_on: :index
    field :extracted_at, as: :date_time, hide_on: :index

    # RAG pipeline
    field :search_text, as: :textarea, hide_on: :index
    field :search_text_generated_at, as: :date_time, hide_on: :index
    field :indexed_at, as: :date_time, hide_on: :index
    field :index_version, as: :number, hide_on: :index

    # File paths
    field :data_path, as: :text, hide_on: :index
    field :mxl_path, as: :text, hide_on: :index
    field :pdf_path, as: :text, hide_on: :index
    field :mid_path, as: :text, hide_on: :index
    field :thumbnail_url, as: :text, hide_on: :index

    # External references
    field :external_url, as: :text, hide_on: :index
    field :external_id, as: :text, hide_on: :index
    field :cpdl_number, as: :text, hide_on: :index
    field :posted_date, as: :date, hide_on: :index

    # Stats
    field :favorites, as: :number, hide_on: :index
    field :rating, as: :number, hide_on: :index

    # Timestamps
    field :created_at, as: :date_time, hide_on: :index, sortable: true
    field :updated_at, as: :date_time, hide_on: :index, sortable: true
    field :deleted_at, as: :date_time, hide_on: [:index, :edit], sortable: true
  end

  # Filters for the index view
  def filters
    filter Avo::Filters::ScoreStatusFilter
    filter Avo::Filters::ScoreSourceFilter
    filter Avo::Filters::ScoreRagStatusFilter
  end

  # Actions
  def actions
    action Avo::Actions::SoftDeleteScores
    action Avo::Actions::RestoreScores
  end
end
