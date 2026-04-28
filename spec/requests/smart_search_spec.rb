require "rails_helper"

RSpec.describe "SmartSearch", type: :request do
  describe "GET /search/ai" do
    let(:query) { "easy bach for piano" }
    let(:rag_payload) {
      {
        "recommendations" => [
          { "score_id" => 101, "title" => "t", "explanation" => "e", "rank" => 1 }
        ],
        "summary" => "ok", "success" => true
      }
    }

    context "with blank query" do
      it "renders the empty form without consuming quota" do
        expect(SmartSearchUsage).not_to receive(:try_consume!)
        get smart_search_path
        expect(response).to have_http_status(:ok)
      end
    end

    context "happy path" do
      it "consumes a quota slot, calls RAG, persists a SmartSearchQuery, and renders results" do
        allow(RagSearch).to receive(:smart_search).and_return(RagSearch::Result.new(rag_payload))

        expect {
          get smart_search_path(q: query)
        }.to change { SmartSearchQuery.count }.by(1)
          .and change { SmartSearchUsage.where(date: SmartSearchUsage.utc_today).pick(:count).to_i }.from(0).to(1)

        record = SmartSearchQuery.last
        expect(record.query).to eq(query)
        expect(record.query_type).to eq("initial")
        expect(record.score_ids).to eq([101])
        expect(record.ip_hash).to be_present
        expect(response).to have_http_status(:ok)
      end
    end

    context "when RagSearch raises" do
      it "refunds the slot and renders the rag_error response" do
        allow(RagSearch).to receive(:smart_search).and_raise(StandardError, "boom")

        expect {
          get smart_search_path(q: query)
        }.not_to change { SmartSearchQuery.count }

        expect(SmartSearchUsage.where(date: SmartSearchUsage.utc_today).pick(:count).to_i).to eq(0)
        expect(response).to have_http_status(:service_unavailable)
      end
    end

    context "when persistence fails" do
      it "refunds the slot" do
        allow(RagSearch).to receive(:smart_search).and_return(RagSearch::Result.new(rag_payload))
        allow(SmartSearchQuery).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(SmartSearchQuery.new))

        expect {
          get smart_search_path(q: query)
        }.not_to change { SmartSearchQuery.count }

        expect(SmartSearchUsage.where(date: SmartSearchUsage.utc_today).pick(:count).to_i).to eq(0)
      end
    end

    context "when at the daily cap" do
      it "returns 429 and renders quota_exhausted" do
        SmartSearchUsage.create!(date: SmartSearchUsage.utc_today, count: 20)
        get smart_search_path(q: query)
        expect(response).to have_http_status(:too_many_requests)
      end
    end

    context "recent-query replay" do
      it "renders cached results without consuming a slot or calling RagSearch" do
        cached = create(:smart_search_query, query: query, created_at: 30.minutes.ago)
        expect(RagSearch).not_to receive(:smart_search)

        expect {
          get smart_search_path(q: "  Easy Bach For Piano  ")
        }.not_to change { SmartSearchQuery.count }

        expect(SmartSearchUsage.where(date: SmartSearchUsage.utc_today).count).to eq(0)
        expect(response).to have_http_status(:ok)
      end

      it "does NOT match an old row" do
        create(:smart_search_query, query: query, created_at: 8.hours.ago)
        allow(RagSearch).to receive(:smart_search).and_return(RagSearch::Result.new(rag_payload))

        expect {
          get smart_search_path(q: query)
        }.to change { SmartSearchQuery.count }.by(1)
      end

      it "does NOT match a row with error set" do
        create(:smart_search_query, query: query, error: "RAG down", created_at: 30.minutes.ago)
        allow(RagSearch).to receive(:smart_search).and_return(RagSearch::Result.new(rag_payload))

        expect {
          get smart_search_path(q: query)
        }.to change { SmartSearchQuery.count }.by(1)
      end

      it "does NOT match a row from a different locale" do
        create(:smart_search_query, query: query, locale: "de", created_at: 30.minutes.ago)
        allow(RagSearch).to receive(:smart_search).and_return(RagSearch::Result.new(rag_payload))

        expect {
          get smart_search_path(q: query)
        }.to change { SmartSearchQuery.count }.by(1)
      end
    end

    context "input length cap" do
      it "rejects queries over 500 chars without consuming a slot" do
        expect(RagSearch).not_to receive(:smart_search)
        get smart_search_path(q: "x" * 501)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(SmartSearchQuery.count).to eq(0)
        expect(SmartSearchUsage.where(date: SmartSearchUsage.utc_today).count).to eq(0)
      end
    end

    context "per-IP throttle" do
      let(:current_ip_hash) {
        salt = Digest::SHA256.hexdigest("smart_search_ip|#{Rails.application.secret_key_base}")
        Digest::SHA256.hexdigest("#{salt}|127.0.0.1")
      }

      it "returns 429 and renders per_ip_limit_reached when 5 successful queries exist in last 24h" do
        5.times do |i|
          create(:smart_search_query,
                 query: "prev #{i}",
                 ip_hash: current_ip_hash,
                 created_at: 1.hour.ago)
        end
        expect(RagSearch).not_to receive(:smart_search)

        get smart_search_path(q: "another query")

        expect(response).to have_http_status(:too_many_requests)
        expect(SmartSearchUsage.where(date: SmartSearchUsage.utc_today).count).to eq(0)
      end

      it "passes through when prior queries have error set" do
        5.times do |i|
          create(:smart_search_query,
                 query: "errored #{i}",
                 ip_hash: current_ip_hash,
                 error: "RAG down",
                 created_at: 1.hour.ago)
        end
        allow(RagSearch).to receive(:smart_search).and_return(RagSearch::Result.new(rag_payload))

        expect { get smart_search_path(q: "fresh query") }.to change { SmartSearchQuery.count }.by(1)
        expect(response).to have_http_status(:ok)
      end

      it "is per-IP, not global — a different ip_hash still passes" do
        5.times do |i|
          create(:smart_search_query,
                 query: "other ip #{i}",
                 ip_hash: Digest::SHA256.hexdigest("different|#{i}"),
                 created_at: 1.hour.ago)
        end
        allow(RagSearch).to receive(:smart_search).and_return(RagSearch::Result.new(rag_payload))

        expect { get smart_search_path(q: query) }.to change { SmartSearchQuery.count }.by(1)
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
