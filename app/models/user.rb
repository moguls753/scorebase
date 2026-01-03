# == Schema Information
#
# Table name: users
#
#  id                    :integer          not null, primary key
#  email_address         :string           not null
#  password_digest       :string           not null
#  search_count_reset_at :datetime
#  smart_search_count    :integer          default(0), not null
#  subscribed_until      :datetime
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  stripe_customer_id    :string
#
# Indexes
#
#  index_users_on_email_address       (email_address) UNIQUE
#  index_users_on_stripe_customer_id  (stripe_customer_id) UNIQUE
#
class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  generates_token_for :password_reset, expires_in: 15.minutes do
    password_salt&.last(10)
  end

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, allow_nil: true

  # Returns true if user has an active Pro subscription
  def pro?
    subscribed_until.present? && subscribed_until > Time.current
  end

  # Search limits: Free users get 3 lifetime, Pro users get 100/month
  FREE_SEARCH_LIMIT = 3
  PRO_MONTHLY_LIMIT = 100
  PRO_PRICE = "$2.99"

  def search_limit
    pro? ? PRO_MONTHLY_LIMIT : FREE_SEARCH_LIMIT
  end

  def searches_remaining
    [search_limit - smart_search_count, 0].max
  end

  def can_smart_search?
    searches_remaining > 0
  end

  def use_smart_search!
    ensure_monthly_reset!
    increment!(:smart_search_count)
  end

  # Call this before checking limits for pro users to ensure count is current
  def ensure_monthly_reset!
    return unless pro?
    return if search_count_reset_at.present? && search_count_reset_at >= Time.current.beginning_of_month

    update!(smart_search_count: 0, search_count_reset_at: Time.current)
    reload
  end
end
