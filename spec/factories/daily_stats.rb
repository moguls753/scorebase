# == Schema Information
#
# Table name: daily_stats
#
#  id         :integer          not null, primary key
#  date       :date
#  smd_clicks :integer          default(0)
#  visits     :integer          default(0)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_daily_stats_on_date  (date) UNIQUE
#
FactoryBot.define do
  factory :daily_stat do
    date { Date.current }
    visits { rand(100..10000) }
    smd_clicks { rand(0..50) }

    trait :yesterday do
      date { Date.yesterday }
    end

    trait :last_week do
      date { 1.week.ago.to_date }
    end
  end
end
