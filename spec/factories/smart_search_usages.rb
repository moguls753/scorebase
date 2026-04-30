# == Schema Information
#
# Table name: smart_search_usages
#
#  id         :integer          not null, primary key
#  count      :integer          default(0), not null
#  date       :date             not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_smart_search_usages_on_date  (date) UNIQUE
#
FactoryBot.define do
  factory :smart_search_usage do
    date  { Time.current.utc.to_date }
    count { 0 }
  end
end
