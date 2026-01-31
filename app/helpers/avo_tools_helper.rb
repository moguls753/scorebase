module AvoToolsHelper
  def country_flag_emoji(code)
    return "" unless code.is_a?(String) && code.length == 2
    code.upcase.codepoints.map { |c| (c + 127397).chr(Encoding::UTF_8) }.join
  end

  def browser_color(browser)
    case browser
    when "Chrome" then "bg-gradient-to-r from-yellow-400 via-red-500 to-green-500"
    when "Firefox" then "bg-gradient-to-r from-orange-500 to-orange-600"
    when "Safari" then "bg-gradient-to-r from-blue-400 to-blue-500"
    when "Edge" then "bg-gradient-to-r from-blue-600 to-cyan-500"
    when "Opera" then "bg-gradient-to-r from-red-500 to-red-600"
    else "bg-gradient-to-r from-gray-400 to-gray-500"
    end
  end

  def country_name(code)
    Avo::ToolsController::COUNTRY_NAMES[code] || code
  end

  def percentage(count, total)
    return 0 if total.zero?
    ((count.to_f / total) * 100).round(1)
  end
end
