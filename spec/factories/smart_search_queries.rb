# == Schema Information
#
# Table name: smart_search_queries
#
#  id                  :integer          not null, primary key
#  error               :text
#  ip_hash             :string(64)       not null
#  locale              :string(2)        not null
#  query               :text             not null
#  query_type          :string           not null
#  rag_recommendations :text
#  rag_summary         :text
#  response_time_ms    :integer
#  result_count        :integer          default(0), not null
#  score_ids           :text             default([]), not null
#  created_at          :datetime         not null
#  parent_query_id     :integer
#
# Indexes
#
#  idx_normalized_query_created_at                (LOWER(TRIM(query)), created_at)
#  idx_one_refinement_per_parent                  (parent_query_id) UNIQUE WHERE query_type = 'refinement'
#  index_smart_search_queries_on_created_at       (created_at)
#  index_smart_search_queries_on_ip_hash          (ip_hash)
#  index_smart_search_queries_on_parent_query_id  (parent_query_id)
#
# Foreign Keys
#
#  parent_query_id  (parent_query_id => smart_search_queries.id) ON DELETE => nullify
#
FactoryBot.define do
  factory :smart_search_query do
    query        { "easy bach for piano" }
    query_type   { "initial" }
    ip_hash      { Digest::SHA256.hexdigest("test|1.2.3.4") }
    result_count { 3 }
    score_ids    { [101, 102, 103] }
    rag_summary  { "Three Bach pieces for intermediate students." }
    rag_recommendations do
      [
        { "score_id" => 101, "title" => "Invention 1",  "explanation" => "Grade 4 fits.",                    "rank" => 1 },
        { "score_id" => 102, "title" => "Minuet in G",  "explanation" => "Approachable counterpoint.",       "rank" => 2 },
        { "score_id" => 103, "title" => "Prelude in C", "explanation" => "Beautiful and tractable at grade 4.", "rank" => 3 }
      ]
    end
    response_time_ms { 800 }
    locale { "en" }

    factory :refinement_query do
      query_type { "refinement" }
      query      { "actually for a 6-year-old" }
      association :parent_query, factory: :smart_search_query
    end
  end
end
