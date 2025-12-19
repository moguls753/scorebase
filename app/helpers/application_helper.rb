module ApplicationHelper
  # Sanitize URL to prevent javascript: XSS attacks
  # Returns nil for unsafe URLs, allowing link_to to handle gracefully
  def safe_external_url(url)
    return nil if url.blank?

    uri = URI.parse(url.to_s.strip)
    uri.scheme&.match?(/\Ahttps?\z/i) ? url : nil
  rescue URI::InvalidURIError
    nil
  end
end
