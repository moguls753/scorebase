module AvoToolsHelper
  def country_flag_emoji(code)
    return "" unless code.is_a?(String) && code.length == 2
    code.upcase.codepoints.map { |c| (c + 127397).chr(Encoding::UTF_8) }.join
  end

  def country_name(code)
    Avo::ToolsController::COUNTRY_NAMES[code] || code
  end

  def percentage(count, total)
    return 0 if total.zero?
    ((count.to_f / total) * 100).round(1)
  end

  def extract_score_id(path)
    path[%r{/scores/(\d+)}, 1]&.to_i
  end
end
