FactoryBot.define do
  factory :smart_search_usage do
    date  { Time.current.utc.to_date }
    count { 0 }
  end
end
