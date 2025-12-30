# Preview all emails at http://localhost:3000/rails/mailers/waitlist_mailer
class WaitlistMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/waitlist_mailer/confirmation_en
  def confirmation_en
    signup = WaitlistSignup.new(email: "pianist@example.com", locale: "en")
    WaitlistMailer.confirmation(signup)
  end

  # Preview this email at http://localhost:3000/rails/mailers/waitlist_mailer/confirmation_de
  def confirmation_de
    signup = WaitlistSignup.new(email: "pianist@example.com", locale: "de")
    WaitlistMailer.confirmation(signup)
  end
end
