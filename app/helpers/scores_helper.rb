module ScoresHelper
  # Single source of truth for filter parameters
  FILTER_PARAMS = %i[key time voicing voice_type genre period source difficulty language].freeze

  # Count active filters from params
  def active_filters_count
    FILTER_PARAMS.count { |param| params[param].present? }
  end

  # Generate hidden fields for all filter params to preserve state across forms
  def filter_hidden_fields(form)
    safe_join(FILTER_PARAMS.map { |param| form.hidden_field(param, value: params[param]) })
  end

  # ─────────────────────────────────────────────────────────────────
  # Score Show Page Helpers
  # ─────────────────────────────────────────────────────────────────

  # Section header with icon and title
  # Usage: score_section_header("♪", "score.music_details")
  def score_section_header(icon, title_key)
    content_tag(:h3, class: "score-section-header") do
      content_tag(:span, icon, class: "score-section-icon") + t(title_key)
    end
  end

  # Render a detail item for the metadata grid
  # Returns nil if value is blank (safe to chain without conditionals)
  def score_detail_item(label_key, value, full_width: false, mono: false)
    return if value.blank?

    css_class = "score-detail-item"
    css_class += " score-detail-item-full" if full_width

    content_tag(:div, class: css_class) do
      content_tag(:dt, t(label_key)) +
        content_tag(:dd, value, class: mono ? "font-mono" : nil)
    end
  end
end
