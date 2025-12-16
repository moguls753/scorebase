# == Schema Information
#
# Table name: composer_mappings
#
#  id              :integer          not null, primary key
#  normalized_name :string
#  original_name   :string           not null
#  source          :string
#  verified        :boolean          default(FALSE), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_composer_mappings_on_normalized_name  (normalized_name)
#  index_composer_mappings_on_original_name    (original_name) UNIQUE
#
FactoryBot.define do
  factory :composer_mapping do
    original_name { Faker::Name.name }
    normalized_name { "#{Faker::Name.last_name}, #{Faker::Name.first_name}" }
    confidence { rand(0.8..1.0).round(2) }

    trait :high_confidence do
      confidence { rand(0.95..1.0).round(2) }
    end

    trait :low_confidence do
      confidence { rand(0.5..0.7).round(2) }
    end

    trait :exact_match do
      confidence { 1.0 }
    end
  end
end
