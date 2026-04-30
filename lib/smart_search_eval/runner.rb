# frozen_string_literal: true

require "json"
require "yaml"
require "net/http"
require "uri"
require "fileutils"
require "time"

module SmartSearchEval
  # Drives a comprehensive eval run: loads the query corpus, hits the RAG service
  # at three layers (vector / smart-search / smart-refine), joins results against
  # the local Score catalog, and writes a single JSON file capturing everything.
  class Runner
    DEFAULT_RAG_URL = "http://localhost:8001"
    DEFAULT_QUERIES = "eval/smart_search_queries.yml"
    DEFAULT_OUTPUT_DIR = "eval/runs"

    attr_reader :rag_url, :queries_path, :output_dir

    def initialize(rag_url: nil, queries_path: nil, output_dir: nil)
      @rag_url = rag_url || ENV.fetch("RAG_URL", DEFAULT_RAG_URL)
      @queries_path = queries_path || ENV.fetch("QUERIES", Rails.root.join(DEFAULT_QUERIES).to_s)
      @output_dir = output_dir || Rails.root.join(DEFAULT_OUTPUT_DIR).to_s
    end

    def run
      FileUtils.mkdir_p(output_dir)
      timestamp = Time.now.utc.strftime("%Y%m%d-%H%M%S")
      output_path = File.join(output_dir, "run-#{timestamp}.json")

      yaml = YAML.load_file(queries_path)
      flat_entries = flatten(yaml.fetch("queries"))
      total = flat_entries.size

      results = []
      flat_entries.each_with_index do |(category, entry), i|
        warn "[#{i + 1}/#{total}] #{category}: #{entry["query"] || entry["scenario"]}"
        results << evaluate(category, entry)
      end

      payload = { metadata: build_metadata, results: results }
      File.write(output_path, JSON.pretty_generate(payload))
      print_summary(results)
      warn "\nWrote #{output_path}"
      output_path
    end

    private

    # Flatten the YAML's category-keyed structure into [[category, entry], ...]
    # in deterministic source-order.
    def flatten(categories_hash)
      categories_hash.flat_map do |category, entries|
        Array(entries).map { |entry| [category, entry] }
      end
    end

    def evaluate(category, entry)
      base = {
        category: category,
        language: entry["language"] || "en",
        intent: entry["intent"] || "focused",
        pair_id: entry["pair_id"]
      }.compact

      if category == "synthetic_refinement"
        evaluate_synthetic_refinement(entry, base)
      elsif entry["refinement"]
        evaluate_chained_refinement(entry, base)
      else
        evaluate_query(entry, base)
      end
    end

    # Standard layer 1+2 evaluation
    def evaluate_query(entry, base)
      query = entry["query"]
      record = base.merge(query: query)
      record[:vector] = vector_search(query)
      record[:smart] = smart_search(query)
      record[:index_coverage] = coverage_signal(query)
      record
    end

    # Layer 1+2 then chained refinement using smart-search output as prior turn
    def evaluate_chained_refinement(entry, base)
      query = entry["query"]
      refinement = entry["refinement"]
      record = base.merge(query: query, refinement_text: refinement)
      record[:vector] = vector_search(query)
      record[:smart] = smart_search(query)
      record[:index_coverage] = coverage_signal(query)
      record[:refine] =
        if record[:smart].is_a?(Hash) && record[:smart][:success] && record[:smart][:recommendations].present?
          smart_refine(
            original_query: query,
            refinement: refinement,
            previous_summary: record[:smart][:summary],
            previous_recommendations: record[:smart][:recommendations],
            request_built_from: "smart"
          )
        else
          { skipped: true, reason: "smart-search did not return usable previous turn" }
        end
      record
    end

    # Layer 3 only — synthetic prior turn fed directly to /smart-refine
    def evaluate_synthetic_refinement(entry, base)
      prior = entry.fetch("synthetic_prior_turn")
      refinement = entry.fetch("refinement")
      base.merge(
        scenario: entry["scenario"],
        synthetic_prior_turn: prior,
        refinement_text: refinement,
        refine: smart_refine(
          original_query: prior["original_query"],
          refinement: refinement,
          previous_summary: prior["summary"],
          previous_recommendations: prior["recommendations"],
          request_built_from: "synthetic"
        )
      )
    end

    # ---- HTTP layers ------------------------------------------------------

    def vector_search(query)
      return { skipped: true, reason: "blank query" } if query.to_s.strip.empty?
      timed do
        uri = URI("#{rag_url}/search")
        uri.query = URI.encode_www_form(q: query, top_k: 20)
        response = Net::HTTP.get_response(uri)
        if response.is_a?(Net::HTTPSuccess)
          body = JSON.parse(response.body)
          {
            success: true,
            results: (body["results"] || []).map { |r| with_score_details(r) }
          }
        else
          { success: false, error: response.body.to_s[0, 500], status: response.code }
        end
      end
    rescue StandardError => e
      { success: false, error: "#{e.class}: #{e.message}" }
    end

    def smart_search(query)
      return { skipped: true, reason: "blank query" } if query.to_s.strip.empty?
      timed do
        uri = URI("#{rag_url}/smart-search")
        uri.query = URI.encode_www_form(q: query, top_k: 15)
        response = Net::HTTP.get_response(uri)
        if response.is_a?(Net::HTTPSuccess)
          body = JSON.parse(response.body)
          {
            success: body["success"],
            summary: body["summary"],
            recommendations: (body["recommendations"] || []).map { |r| with_score_details(r) }
          }
        else
          { success: false, error: response.body.to_s[0, 500], status: response.code }
        end
      end
    rescue StandardError => e
      { success: false, error: "#{e.class}: #{e.message}" }
    end

    def smart_refine(original_query:, refinement:, previous_summary:, previous_recommendations:, request_built_from:)
      timed do
        uri = URI("#{rag_url}/smart-refine")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
        request.body = {
          original_query: original_query,
          refinement: refinement,
          previous_summary: previous_summary,
          previous_recommendations: previous_recommendations.map { |r| normalize_prior_pick(r) }
        }.to_json
        response = http.request(request)
        if response.is_a?(Net::HTTPSuccess)
          body = JSON.parse(response.body)
          {
            success: body["success"],
            summary: body["summary"],
            recommendations: (body["recommendations"] || []).map { |r| with_score_details(r) },
            request_built_from: request_built_from
          }
        else
          { success: false, error: response.body.to_s[0, 500], status: response.code, request_built_from: request_built_from }
        end
      end
    rescue StandardError => e
      { success: false, error: "#{e.class}: #{e.message}", request_built_from: request_built_from }
    end

    # ---- Helpers ----------------------------------------------------------

    # Wrap any block that returns a Hash so we attach a response_time_ms field.
    def timed
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).to_i
      result.is_a?(Hash) ? result.merge(response_time_ms: elapsed_ms) : result
    end

    # Adds local-DB-derived score_details to a single recommendation/result hash
    # so the JSON captures composer/instrument/etc. for offline analysis.
    def with_score_details(record)
      record = record.dup
      score_id = record["score_id"]
      score = score_id && Score.find_by(id: score_id)
      record["score_details"] =
        if score
          {
            "composer" => score.composer,
            "primary_instrument" => safe_attr(score, :primary_instrument),
            "difficulty" => safe_attr(score, :pedagogical_grade),
            "period" => safe_attr(score, :period),
            "genre" => safe_attr(score, :genre),
            "num_parts" => safe_attr(score, :num_parts),
            "active" => safe_attr(score, :active?),
            "exists_in_catalog" => true
          }
        else
          { "exists_in_catalog" => false }
        end
      record
    end

    def safe_attr(record, attr)
      record.respond_to?(attr) ? record.public_send(attr) : nil
    rescue StandardError
      nil
    end

    def normalize_prior_pick(rec)
      h = rec.is_a?(Hash) ? rec.transform_keys(&:to_s) : rec.to_h.transform_keys(&:to_s)
      {
        score_id: h["score_id"],
        title: h["title"],
        explanation: h["explanation"],
        rank: h["rank"]
      }
    end

    # Per-query index-coverage signal — a small set of catalog stats we can
    # compute cheaply from the local DB. Helps the analyzer separate "model
    # failed" from "answer wasn't in the candidate pool."
    def coverage_signal(query)
      {
        "indexed_total" => Score.where(rag_status: "indexed").count,
        "catalog_total" => Score.count,
        "active_total" => Score.active.count
      }
    rescue StandardError
      {}
    end

    def build_metadata
      {
        timestamp: Time.now.utc.iso8601,
        rag_url: rag_url,
        llm_backend: ENV.fetch("LLM_BACKEND", "deepseek"),
        llm_model: ENV["DEEPSEEK_MODEL"] || ENV["GROQ_MODEL"] || ENV["LMSTUDIO_MODEL"],
        embedding_model: "paraphrase-multilingual-MiniLM-L12-v2",
        code_sha: git_sha,
        catalog: {
          total_scores: safely { Score.count },
          active_scores: safely { Score.active.count },
          indexed_scores: safely { Score.where(rag_status: "indexed").count },
          most_recent_indexed_at: safely { Score.where(rag_status: "indexed").maximum(:indexed_at)&.iso8601 }
        }
      }
    end

    def git_sha
      `git rev-parse HEAD`.strip
    rescue StandardError
      nil
    end

    def safely
      yield
    rescue StandardError
      nil
    end

    def print_summary(results)
      total = results.size
      smart_failures = results.count { |r| r[:smart].is_a?(Hash) && r[:smart][:success] == false }
      vector_times = results.map { |r| r.dig(:vector, :response_time_ms) }.compact.sort
      smart_times = results.map { |r| r.dig(:smart, :response_time_ms) }.compact.sort
      refine_times = results.map { |r| r.dig(:refine, :response_time_ms) }.compact.sort

      warn "\n=== Run summary ==="
      warn "Queries: #{total}"
      warn "Smart-search failures: #{smart_failures}"
      warn "Vector  p50/p95: #{percentile(vector_times, 50)}ms / #{percentile(vector_times, 95)}ms"
      warn "Smart   p50/p95: #{percentile(smart_times, 50)}ms / #{percentile(smart_times, 95)}ms"
      warn "Refine  p50/p95: #{percentile(refine_times, 50)}ms / #{percentile(refine_times, 95)}ms" if refine_times.any?
    end

    def percentile(sorted, p)
      return "n/a" if sorted.empty?
      k = ((p / 100.0) * (sorted.length - 1)).round.clamp(0, sorted.length - 1)
      sorted[k]
    end
  end
end
