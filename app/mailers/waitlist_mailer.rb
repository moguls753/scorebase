class WaitlistMailer < ApplicationMailer
  def confirmation(waitlist_signup)
    @waitlist_signup = waitlist_signup
    @score_count = Score.count
    locale = waitlist_signup.locale

    I18n.with_locale(locale.to_sym) do
      mail(
        to: waitlist_signup.email,
        subject: I18n.t("waitlist_mailer.confirmation.subject")
      ) do |format|
        format.html { render template: "waitlist_mailer/confirmation_#{locale}" }
        format.text { render template: "waitlist_mailer/confirmation_#{locale}" }
      end
    end
  end
end
