# Mission Control Jobs configuration
# Uses same basic_auth credentials as Avo admin
Rails.application.configure do
  MissionControl::Jobs.http_basic_auth_user = Rails.application.credentials.dig(:basic_auth, :user) || "admin"
  MissionControl::Jobs.http_basic_auth_password = Rails.application.credentials.dig(:basic_auth, :password)
end
