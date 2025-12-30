class WaitlistMailer < ApplicationMailer
  def confirmation(waitlist_signup)
    @waitlist_signup = waitlist_signup
    locale = waitlist_signup.locale.to_sym

    I18n.with_locale(locale) do
      mail(
        to: waitlist_signup.email,
        subject: I18n.t("waitlist_mailer.confirmation.subject"),
        template_name: "confirmation.#{waitlist_signup.locale}"
      )
    end
  end
end
