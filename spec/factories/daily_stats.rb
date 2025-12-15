FactoryBot.define do
  factory :daily_stat do
    date { Date.current }
    visits { rand(100..10000) }
    unique_visitors { rand(50..5000) }

    trait :yesterday do
      date { Date.yesterday }
    end

    trait :last_week do
      date { 1.week.ago.to_date }
    end
  end
end
