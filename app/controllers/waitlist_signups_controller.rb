class WaitlistSignupsController < ApplicationController
  before_action :check_rate_limit, only: :create

  def create
    @waitlist_signup = WaitlistSignup.new(waitlist_signup_params)
    @waitlist_signup.locale = I18n.locale.to_s

    if @waitlist_signup.save
      begin
        WaitlistMailer.confirmation(@waitlist_signup).deliver_later
      rescue StandardError => e
        Rails.logger.error("Failed to queue waitlist email: #{e.message}")
      end

      render json: { success: true, message: I18n.t("waitlist.success") }, status: :created
    else
      if @waitlist_signup.errors.of_kind?(:email, :taken)
        render json: { success: true, message: I18n.t("waitlist.already_subscribed") }, status: :ok
      else
        render json: { success: false, errors: @waitlist_signup.errors.full_messages }, status: :unprocessable_entity
      end
    end
  end

  private

  def waitlist_signup_params
    params.require(:waitlist_signup).permit(:email)
  end

  def check_rate_limit
    cache_key = "waitlist_signup:#{request.remote_ip}"
    count = Rails.cache.read(cache_key) || 0

    if count >= 5
      render json: { success: false, errors: [I18n.t("waitlist.rate_limit")] }, status: :too_many_requests
      return
    end

    Rails.cache.write(cache_key, count + 1, expires_in: 1.hour)
  end
end
