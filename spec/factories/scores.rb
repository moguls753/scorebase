# == Schema Information
#
# Table name: scores
#
#  id                   :integer          not null, primary key
#  complexity           :integer
#  composer             :string
#  cpdl_number          :string
#  data_path            :string
#  description          :text
#  editor               :string
#  external_url         :string
#  favorites            :integer          default(0)
#  genres               :text
#  instruments          :string
#  key_signature        :string
#  language             :string
#  license              :string
#  lyrics               :text
#  metadata_path        :string
#  mid_path             :string
#  mxl_path             :string
#  normalization_status :string           default("pending"), not null
#  num_parts            :integer
#  page_count           :integer
#  pdf_path             :string
#  posted_date          :date
#  rating               :decimal(3, 2)
#  source               :string           default("pdmx")
#  tags                 :text
#  thumbnail_url        :string
#  time_signature       :string
#  title                :string
#  views                :integer          default(0)
#  voicing              :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  external_id          :string
#
# Indexes
#
#  index_scores_on_complexity            (complexity)
#  index_scores_on_composer              (composer)
#  index_scores_on_external_id           (external_id)
#  index_scores_on_genres                (genres)
#  index_scores_on_instruments           (instruments)
#  index_scores_on_key_signature         (key_signature)
#  index_scores_on_normalization_status  (normalization_status)
#  index_scores_on_num_parts             (num_parts)
#  index_scores_on_rating                (rating)
#  index_scores_on_source                (source)
#  index_scores_on_time_signature        (time_signature)
#  index_scores_on_views                 (views)
#  index_scores_on_voicing               (voicing)
#
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
