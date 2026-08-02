module ApplicationHelper
  def hreflang_alternates
    path = request.path.sub(%r{\A/de(?=/|\z)}, "").presence || "/"
    { en: path, de: "/de#{path}".chomp("/") }
  end

  # Sanitize URL to prevent javascript: XSS attacks
  # Returns nil for unsafe URLs, allowing link_to to handle gracefully
  def safe_external_url(url)
    return nil if url.blank?

    uri = URI.parse(url.to_s.strip)
    uri.scheme&.match?(/\Ahttps?\z/i) ? url : nil
  rescue URI::InvalidURIError
    nil
  end

  # Check if the current user is authenticated as admin (via Avo)
  def admin_signed_in?
    session[:admin_authenticated] == true
  end

  # Generate Avo admin edit path for a record
  def avo_edit_path(record)
    resource_name = record.class.name.underscore.pluralize
    "/admin/resources/#{resource_name}/#{record.id}/edit"
  end
end
