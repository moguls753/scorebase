require "rails_helper"

RSpec.describe SmartSearchQuery, type: :model do
  describe "validations" do
    it "validates query presence" do
      record = build(:smart_search_query, query: "")
      expect(record).not_to be_valid
      expect(record.errors[:query]).to include("can't be blank")
    end

    it "rejects query over 500 chars" do
      record = build(:smart_search_query, query: "a" * 501)
      expect(record).not_to be_valid
    end

    it "validates query_type inclusion" do
      expect { build(:smart_search_query, query_type: "weird") }.to raise_error(ArgumentError) # enum rejects unknown values
    end

    it "requires parent_query_id on a refinement" do
      record = build(:smart_search_query, query_type: "refinement", parent_query: nil)
      expect(record).not_to be_valid
      expect(record.errors[:parent_query_id]).to include("can't be blank")
    end

    it "rejects refinement whose parent is itself a refinement" do
      level1 = create(:smart_search_query)
      level2 = create(:refinement_query, parent_query: level1)
      level3 = build(:smart_search_query, query_type: "refinement", parent_query: level2)
      expect(level3).not_to be_valid
      expect(level3.errors[:parent_query]).to include("must be an initial query")
    end

    it "rejects a second refinement against the same parent" do
      parent = create(:smart_search_query)
      create(:refinement_query, parent_query: parent)
      second = build(:smart_search_query, query_type: "refinement", parent_query: parent)
      expect(second).not_to be_valid
      expect(second.errors[:parent_query]).to include("has already been refined")
    end

    it "rejects a duplicate refinement at the DB level when validation is bypassed" do
      parent = create(:smart_search_query)
      create(:refinement_query, parent_query: parent)
      duplicate = build(:smart_search_query, query_type: "refinement", parent_query: parent)
      expect { duplicate.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "JSON serialization" do
    it "round-trips score_ids" do
      record = create(:smart_search_query, score_ids: [9, 8, 7])
      expect(record.reload.score_ids).to eq([9, 8, 7])
    end

    it "round-trips rag_recommendations" do
      record = create(:smart_search_query)
      expect(record.reload.rag_recommendations.first["score_id"]).to eq(101)
    end
  end

  describe "before_save :truncate_rag_fields" do
    it "clips rag_summary to 1000 chars" do
      record = create(:smart_search_query, rag_summary: "x" * 1500)
      expect(record.reload.rag_summary.length).to eq(1000)
    end

    it "clips each explanation to 500 chars" do
      long = "y" * 800
      recs = [{ "score_id" => 1, "title" => "t", "explanation" => long, "rank" => 1 }]
      record = create(:smart_search_query, rag_recommendations: recs)
      expect(record.reload.rag_recommendations.first["explanation"].length).to eq(500)
    end

    it "clips rag_recommendations to 5 entries" do
      recs = (1..7).map { |i| { "score_id" => i, "title" => "t", "explanation" => "e", "rank" => i } }
      record = create(:smart_search_query, rag_recommendations: recs)
      expect(record.reload.rag_recommendations.size).to eq(5)
    end
  end

  describe ".recent_ip_count" do
    let(:hash) { Digest::SHA256.hexdigest("test|abc") }

    it "counts successful queries from the same ip_hash in the window" do
      3.times { create(:smart_search_query, ip_hash: hash, created_at: 30.minutes.ago) }
      expect(SmartSearchQuery.recent_ip_count(hash)).to eq(3)
    end

    it "ignores rows with error set" do
      create(:smart_search_query, ip_hash: hash, error: "RAG down", created_at: 30.minutes.ago)
      expect(SmartSearchQuery.recent_ip_count(hash)).to eq(0)
    end

    it "ignores rows older than the window" do
      create(:smart_search_query, ip_hash: hash, created_at: 30.hours.ago)
      expect(SmartSearchQuery.recent_ip_count(hash)).to eq(0)
    end

    it "ignores rows from other ip_hashes" do
      create(:smart_search_query, ip_hash: Digest::SHA256.hexdigest("other"), created_at: 30.minutes.ago)
      expect(SmartSearchQuery.recent_ip_count(hash)).to eq(0)
    end
  end

  describe ".recent_initial_for" do
    it "matches case- and whitespace-insensitively within the TTL" do
      create(:smart_search_query, query: "Easy Bach", created_at: 30.minutes.ago)
      expect(SmartSearchQuery.recent_initial_for("  easy bach  ")).to be_present
    end

    it "returns the most recent matching row when several match" do
      create(:smart_search_query, query: "Easy Bach", created_at: 5.hours.ago)
      newer = create(:smart_search_query, query: "easy bach", created_at: 30.minutes.ago)
      expect(SmartSearchQuery.recent_initial_for("Easy Bach")).to eq(newer)
    end

    it "does not match a row older than the TTL" do
      create(:smart_search_query, query: "old query", created_at: 8.hours.ago)
      expect(SmartSearchQuery.recent_initial_for("old query")).to be_nil
    end

    it "skips rows with error set" do
      create(:smart_search_query, query: "bad", error: "RAG down")
      expect(SmartSearchQuery.recent_initial_for("bad")).to be_nil
    end

    it "skips refinement rows" do
      parent = create(:smart_search_query, query: "parent text")
      create(:refinement_query, query: "child text", parent_query: parent)
      expect(SmartSearchQuery.recent_initial_for("child text")).to be_nil
    end
  end

  describe "#refinable?" do
    it "is true for an initial query with summary, recommendations, and no refinements" do
      record = create(:smart_search_query)
      expect(record).to be_refinable
    end

    it "is false when summary is blank" do
      record = create(:smart_search_query, rag_summary: nil)
      expect(record).not_to be_refinable
    end

    it "is false when recommendations are empty" do
      record = create(:smart_search_query, rag_recommendations: [])
      expect(record).not_to be_refinable
    end

    it "is false when a refinement already exists" do
      record = create(:smart_search_query)
      create(:refinement_query, parent_query: record)
      expect(record.reload).not_to be_refinable
    end
  end
end
