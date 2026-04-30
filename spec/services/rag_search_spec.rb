require "rails_helper"

RSpec.describe RagSearch do
  describe "Result.from_query_record" do
    it "rebuilds a Result with recommendations, summary, and success: true" do
      record = create(:smart_search_query)
      result = RagSearch::Result.from_query_record(record)

      expect(result.success).to be true
      expect(result.summary).to eq(record.rag_summary)
      expect(result.score_ids).to eq(record.score_ids)
      expect(result.explanation_for(101)).to eq("Grade 4 fits.")
    end

    it "falls back to 'No results found.' when rag_summary is nil" do
      record = create(:smart_search_query, rag_summary: nil)
      result = RagSearch::Result.from_query_record(record)

      expect(result.success).to be true
      expect(result.summary).to eq("No results found.")
    end
  end

  describe ".smart_refine" do
    let(:body) {
      {
        original_query: "easy bach",
        refinement: "for a 6-year-old",
        previous_summary: "Three Bach pieces…",
        previous_recommendations: [
          { "score_id" => 1, "title" => "t", "explanation" => "e", "rank" => 1 }
        ]
      }
    }

    it "POSTs JSON to /smart-refine and returns a Result on 200" do
      stub_response = {
        "recommendations" => [{ "score_id" => 9, "title" => "x", "explanation" => "y", "rank" => 1 }],
        "summary" => "ok", "success" => true
      }.to_json

      stub_request(:post, "#{RagSearch::RAG_API_URL}/smart-refine")
        .with(headers: { "Content-Type" => "application/json" }, body: hash_including(body.transform_keys(&:to_s)))
        .to_return(status: 200, body: stub_response, headers: { "Content-Type" => "application/json" })

      result = RagSearch.smart_refine(**body)
      expect(result.success).to be true
      expect(result.score_ids).to eq([9])
    end

    it "returns a non-success Result when the endpoint returns non-2xx" do
      stub_request(:post, "#{RagSearch::RAG_API_URL}/smart-refine")
        .to_return(status: 503, body: '{"detail":"down"}')

      result = RagSearch.smart_refine(**body)
      expect(result.success).to be false
    end
  end
end
