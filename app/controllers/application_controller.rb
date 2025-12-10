class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Protect production site during testing phase
  # Remove this once ready to launch publicly
  # Set password via: rails credentials:edit
  # Add: basic_auth: { user: "admin", password: "your_password" }
  http_basic_authenticate_with(
    name: Rails.application.credentials.dig(:basic_auth, :user) || "admin",
    password: Rails.application.credentials.dig(:basic_auth, :password),
    if: -> { Rails.env.production? && Rails.application.credentials.dig(:basic_auth, :password).present? }
  )
end
