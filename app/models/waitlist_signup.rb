# == Schema Information
#
# Table name: waitlist_signups
#
#  id         :integer          not null, primary key
#  email      :string           not null
#  locale     :string           default("en"), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_waitlist_signups_on_email  (email) UNIQUE
#
class WaitlistSignup < ApplicationRecord
  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP },
                    length: { maximum: 255 }
  validates :locale, presence: true, inclusion: { in: %w[en de] }

  before_validation :normalize_email

  private

  def normalize_email
    self.email = email.to_s.downcase.strip
  end
end
