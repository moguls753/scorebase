FactoryBot.define do
  factory :score do
    sequence(:title) { |n| "Test Score #{n}" }
    sequence(:data_path) { |n| "scores/test_#{n}/score.musicxml" }
    source { "pdmx" }
    composer { "Bach, Johann Sebastian" }

    trait :cpdl do
      source { "cpdl" }
      external_id { "12345" }
    end

    trait :imslp do
      source { "imslp" }
      external_id { "67890" }
    end

    trait :with_pdf do
      pdf_path { "test.pdf" }
    end
  end
end
