FactoryBot.define do
  factory :smart_search_feedback do
    association :smart_search_query
    sequence(:ip_hash) { |n| Digest::SHA256.hexdigest("test|#{n}") }
    verdict { "good" }
    comment { nil }
  end
end
