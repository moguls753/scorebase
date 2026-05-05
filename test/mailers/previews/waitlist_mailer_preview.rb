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

  # Preview this email at http://localhost:3000/rails/mailers/waitlist_mailer/beta_update_en
  def beta_update_en
    signup = WaitlistSignup.new(email: "pianist@example.com", locale: "en")
    WaitlistMailer.beta_update(signup)
  end

  # Preview this email at http://localhost:3000/rails/mailers/waitlist_mailer/beta_update_de
  def beta_update_de
    signup = WaitlistSignup.new(email: "pianist@example.com", locale: "de")
    WaitlistMailer.beta_update(signup)
  end
end
