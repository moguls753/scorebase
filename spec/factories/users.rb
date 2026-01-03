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
FactoryBot.define do
  factory :user do
    sequence(:email_address) { |n| "user#{n}@example.com" }
    password { "password123" }
    password_confirmation { "password123" }

    trait :pro do
      subscribed_until { 1.month.from_now }
      sequence(:stripe_customer_id) { |n| "cus_test#{n}" }
    end
  end
end
