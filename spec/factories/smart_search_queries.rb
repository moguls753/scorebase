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
