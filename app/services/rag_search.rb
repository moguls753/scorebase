# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

class RagSearch
  RAG_API_URL = ENV.fetch("RAG_API_URL", "http://localhost:8001")

  class Result
    attr_reader :recommendations, :summary, :success

    def initialize(data)
      @recommendations = data["recommendations"] || []
      @summary = data["summary"] || "No results found."
      @success = data["success"] != false
    end

    def self.from_query_record(record)
      new(
        "recommendations" => record.rag_recommendations || [],
        "summary"         => record.rag_summary.presence || "No results found.",
        "success"         => true
      )
    end

    def score_ids
      recommendations.map { |r| r["score_id"] }
    end

    def explanation_for(score_id)
      rec = recommendations.find { |r| r["score_id"] == score_id }
      rec&.dig("explanation")
    end

    def empty?
      recommendations.empty?
    end
  end

  class << self
    def smart_search(query, top_k: 15)
      uri = URI("#{RAG_API_URL}/smart-search")
      uri.query = URI.encode_www_form(q: query, top_k: top_k)

      response = Net::HTTP.get_response(uri)

      if response.is_a?(Net::HTTPSuccess)
        Result.new(JSON.parse(response.body))
      else
        Rails.logger.error("RAG API error: #{response.code} - #{response.body}")
        Result.new({ "summary" => "Smart search is temporarily unavailable.", "success" => false })
      end
    rescue StandardError => e
      Rails.logger.error("RAG API connection failed: #{e.message}")
      Result.new({ "summary" => "Could not connect to search service.", "success" => false })
    end

    def smart_refine(original_query:, refinement:, previous_summary:, previous_recommendations:)
      uri = URI("#{RAG_API_URL}/smart-refine")
      payload = {
        original_query: original_query,
        refinement: refinement,
        previous_summary: previous_summary,
        previous_recommendations: previous_recommendations
      }.to_json

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
      request.body = payload
      response = http.request(request)

      if response.is_a?(Net::HTTPSuccess)
        Result.new(JSON.parse(response.body))
      else
        Rails.logger.error("RAG /smart-refine error: #{response.code} - #{response.body}")
        Result.new({ "summary" => "Refinement is temporarily unavailable.", "success" => false })
      end
    rescue StandardError => e
      Rails.logger.error("RAG /smart-refine connection failed: #{e.message}")
      Result.new({ "summary" => "Could not connect to refinement service.", "success" => false })
    end

    def available?
      uri = URI("#{RAG_API_URL}/")
      response = Net::HTTP.get_response(uri)
      response.is_a?(Net::HTTPSuccess)
    rescue StandardError
      false
    end
  end
end
