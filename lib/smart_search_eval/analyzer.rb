# frozen_string_literal: true

require "json"
require "set"

module SmartSearchEval
  # Reads a runner JSON output and computes objective metrics:
  # - Throughput (per-layer p50/p95)
  # - Hallucination rate (returned IDs not in catalog)
  # - Composer / instrument heuristic match
  # - Vector→LLM overlap (does smart-search pick from the vector top-N?)
  # - Unique-score coverage (LLM diversity across queries)
  # - Refinement shift (do refined picks differ from initial?)
  # - Failure/edge-case roll-up
  # - Bilingual pair comparison (pair_id) — overlap between EN and DE picks
  #
  # Subjective quality assessment (does pick X actually fit query Y?) is
  # intentionally NOT computed here. Send the JSON to a human/LLM judge for that.
  class Analyzer
    KNOWN_COMPOSERS = {
      "bach" => /\bbach\b/i,
      "mozart" => /\bmozart\b/i,
      "beethoven" => /\bbeethoven\b/i,
      "chopin" => /\bchopin\b/i,
      "schubert" => /\bschubert\b/i,
      "schumann" => /\bschumann\b/i,
      "brahms" => /\bbrahms\b/i,
      "liszt" => /\bliszt\b/i,
      "debussy" => /\bdebussy\b/i,
      "ravel" => /\bravel\b/i,
      "satie" => /\bsatie\b/i,
      "bartok" => /\bbart[óo]k\b/i,
      "prokofiev" => /\bprokofiev\b/i,
      "rachmaninoff" => /\brachmaninoff\b/i,
      "tchaikovsky" => /\btchaikovsky\b/i,
      "vivaldi" => /\bvivaldi\b/i,
      "handel" => /\bh[äa]ndel\b/i,
      "mendelssohn" => /\bmendelssohn\b/i,
      "saint-saens" => /\bsaint-?sa[eë]ns\b/i,
      "pachelbel" => /\bpachelbel\b/i
    }.freeze

    INSTRUMENT_KEYWORDS = {
      "piano" => /\bpiano\b|klavier/i,
      "violin" => /\bviolin\b|geige/i,
      "cello" => /\bcello\b|cell/i,
      "guitar" => /\bguitar\b|gitarre/i,
      "flute" => /\bflute\b|fl[öo]te/i,
      "trumpet" => /\btrumpet\b|trompete/i,
      "organ" => /\borgan\b|orgel/i,
      "harpsichord" => /\bharpsichord\b|cembalo/i,
      "oboe" => /\boboe\b/i,
      "saxophone" => /\bsaxophone\b|saxophon/i,
      "clarinet" => /\bclarinet\b|klarinette/i,
      "viola" => /\bviola\b/i
    }.freeze

    attr_reader :data, :results

    def initialize(json_payload)
      @data = json_payload
      @results = json_payload.fetch("results", json_payload[:results] || [])
    end

    def markdown_report
      lines = []
      lines << "# Smart Search Eval — Analyzer Report"
      lines << ""
      lines << "**Source:** `#{data.dig('metadata', 'timestamp') || data.dig(:metadata, :timestamp)}` · " \
               "model `#{data.dig('metadata', 'llm_model') || 'unknown'}` · " \
               "code `#{(data.dig('metadata', 'code_sha') || 'unknown')[0, 8]}`"
      lines << ""
      lines << "**Queries evaluated:** #{results.size}"
      lines << ""
      lines.concat(throughput_section)
      lines.concat(reliability_section)
      lines.concat(catalog_grounding_section)
      lines.concat(composer_match_section)
      lines.concat(instrument_match_section)
      lines.concat(vector_llm_overlap_section)
      lines.concat(diversity_section)
      lines.concat(refinement_shift_section)
      lines.concat(bilingual_parity_section)
      lines.concat(edge_case_section)
      lines << ""
      lines << "_Subjective quality (does each pick actually fit each query?) requires human/LLM review of the raw JSON._"
      lines.join("\n")
    end

    private

    # ---- Sections --------------------------------------------------------

    def throughput_section
      lines = ["## Throughput", ""]
      [%w[vector vector], %w[smart smart-search], %w[refine smart-refine]].each do |key, label|
        times = results.map { |r| dig(r, key, "response_time_ms") }.compact.sort
        next if times.empty?
        lines << "- **#{label}** — n=#{times.size}  p50: #{percentile(times, 50)}ms  p95: #{percentile(times, 95)}ms  max: #{times.last}ms"
      end
      lines << ""
      lines
    end

    def reliability_section
      lines = ["## Reliability", ""]
      %w[vector smart refine].each do |key|
        ran = results.count { |r| r[key].is_a?(Hash) && !r[key]["skipped"] }
        next if ran.zero?
        failed = results.count { |r| r[key].is_a?(Hash) && r[key]["success"] == false }
        skipped = results.count { |r| r[key].is_a?(Hash) && r[key]["skipped"] }
        lines << "- **#{key}**: #{ran - failed}/#{ran} successful (#{pct(ran - failed, ran)}), #{failed} failed, #{skipped} skipped"
      end
      lines << ""
      lines
    end

    def catalog_grounding_section
      lines = ["## Catalog grounding (hallucination check)", ""]
      total_picks = 0
      hallucinated = 0
      results.each do |r|
        smart_picks = dig(r, "smart", "recommendations") || []
        refine_picks = dig(r, "refine", "recommendations") || []
        (smart_picks + refine_picks).each do |pick|
          total_picks += 1
          hallucinated += 1 unless dig(pick, "score_details", "exists_in_catalog")
        end
      end
      lines << "- LLM picks total: #{total_picks}"
      lines << "- Picks referencing IDs **not in local catalog**: #{hallucinated} (#{pct(hallucinated, total_picks)})"
      lines << "  - These are either hallucinated by the LLM, or scores that exist on prod but aren't in this local DB"
      lines << ""
      lines
    end

    def composer_match_section
      lines = ["## Composer-match heuristic", ""]
      lines << "_For queries that name a known composer, what fraction of smart-search picks are actually by that composer?_"
      lines << ""
      KNOWN_COMPOSERS.each do |name, regex|
        relevant = results.select { |r| r["query"].is_a?(String) && r["query"].match?(regex) }
        next if relevant.empty?
        picks = relevant.flat_map { |r| dig(r, "smart", "recommendations") || [] }
        next if picks.empty?
        matched = picks.count { |p| (dig(p, "score_details", "composer") || "").to_s.match?(regex) }
        lines << "- **#{name}**: #{matched}/#{picks.size} picks match (#{pct(matched, picks.size)}) across #{relevant.size} queries"
      end
      lines << ""
      lines
    end

    def instrument_match_section
      lines = ["## Instrument-match heuristic", ""]
      lines << "_For queries naming an instrument, do the picks match the instrument?_"
      lines << ""
      INSTRUMENT_KEYWORDS.each do |inst, regex|
        relevant = results.select { |r| r["query"].is_a?(String) && r["query"].match?(regex) }
        next if relevant.empty?
        picks = relevant.flat_map { |r| dig(r, "smart", "recommendations") || [] }
        next if picks.empty?
        matched = picks.count { |p| (dig(p, "score_details", "primary_instrument") || "").to_s.match?(regex) }
        lines << "- **#{inst}**: #{matched}/#{picks.size} picks match (#{pct(matched, picks.size)}) across #{relevant.size} queries"
      end
      lines << ""
      lines
    end

    def vector_llm_overlap_section
      lines = ["## Vector → LLM overlap", ""]
      lines << "_Does smart-search pick from the top of the vector results, or surface different scores?_"
      lines << ""
      [3, 5, 10].each do |k|
        overlaps = []
        results.each do |r|
          vec_top_k = (dig(r, "vector", "results") || []).first(k).map { |v| v["score_id"] }
          smart_picks = (dig(r, "smart", "recommendations") || []).map { |s| s["score_id"] }
          next if smart_picks.empty?
          intersect = (vec_top_k & smart_picks).size
          overlaps << intersect.to_f / smart_picks.size
        end
        next if overlaps.empty?
        avg = overlaps.sum / overlaps.size
        lines << "- Smart picks within vector top-#{k}: avg #{(avg * 100).round}% (#{overlaps.count { |o| o > 0 }} of #{overlaps.size} queries had any overlap)"
      end
      lines << ""
      lines
    end

    def diversity_section
      lines = ["## Catalog diversity", ""]
      all_smart_ids = results.flat_map { |r| (dig(r, "smart", "recommendations") || []).map { |p| p["score_id"] } }.compact
      all_refine_ids = results.flat_map { |r| (dig(r, "refine", "recommendations") || []).map { |p| p["score_id"] } }.compact
      total_picks = all_smart_ids.size + all_refine_ids.size
      unique_picks = (all_smart_ids + all_refine_ids).uniq.size
      lines << "- Distinct score_ids returned across all picks: **#{unique_picks}** (out of #{total_picks} pick slots, #{pct(unique_picks, total_picks)} unique)"
      lines << ""

      lines << "### Within-result diversity (focused vs broad intent)"
      lines << ""
      [%w[focused 3], %w[broad 3]].each do |intent, _|
        relevant = results.select { |r| r["intent"] == intent && (dig(r, "smart", "recommendations") || []).any? }
        next if relevant.empty?
        composer_diversity = relevant.map do |r|
          composers = (dig(r, "smart", "recommendations") || []).map { |p| dig(p, "score_details", "composer") }.compact.uniq
          composers.size
        end
        avg_unique_composers = composer_diversity.sum.to_f / composer_diversity.size
        lines << "- intent=`#{intent}` (#{relevant.size} queries): avg distinct composers per result set: **#{avg_unique_composers.round(2)}** of 3"
      end
      lines << ""
      lines
    end

    def refinement_shift_section
      refine_results = results.select { |r| r["refine"].is_a?(Hash) && r["refine"]["success"] }
      return [] if refine_results.empty?
      lines = ["## Refinement shift", ""]
      lines << "_Did refinement actually change the picks? (Higher shift = more responsive to user direction.)_"
      lines << ""
      shifts = refine_results.map do |r|
        prior_ids = if r.dig("refine", "request_built_from") == "synthetic"
          (r.dig("synthetic_prior_turn", "recommendations") || []).map { |p| p["score_id"] }
        else
          (dig(r, "smart", "recommendations") || []).map { |p| p["score_id"] }
        end
        new_ids = (dig(r, "refine", "recommendations") || []).map { |p| p["score_id"] }
        next nil if prior_ids.empty? || new_ids.empty?
        unchanged = (prior_ids & new_ids).size
        unchanged.to_f / new_ids.size
      end.compact
      return [] if shifts.empty?
      avg_unchanged = shifts.sum / shifts.size
      shift = 1.0 - avg_unchanged
      lines << "- Avg shift (1 = totally new picks, 0 = same as before): **#{(shift * 100).round}%**"
      lines << "- #{shifts.count { |s| s == 0.0 }} of #{shifts.size} refinements returned identical picks (no shift)"
      lines << "- Synthetic refinement scenarios: #{refine_results.count { |r| r.dig('refine', 'request_built_from') == 'synthetic' }}"
      lines << ""
      lines
    end

    def bilingual_parity_section
      paired = results.select { |r| r["pair_id"] }
      return [] if paired.empty?
      lines = ["## Bilingual parity (EN ↔ DE)", ""]
      lines << "_Same intent expressed in two languages — do the picks overlap?_"
      lines << ""
      pairs = paired.group_by { |r| r["pair_id"] }
      total = 0
      total_overlap = 0
      pairs.each do |pair_id, items|
        next if items.size != 2
        en = items.find { |i| (i["language"] || "en") == "en" }
        de = items.find { |i| i["language"] == "de" }
        next unless en && de
        en_ids = (dig(en, "smart", "recommendations") || []).map { |p| p["score_id"] }
        de_ids = (dig(de, "smart", "recommendations") || []).map { |p| p["score_id"] }
        next if en_ids.empty? || de_ids.empty?
        intersect = (en_ids & de_ids).size
        total += en_ids.size
        total_overlap += intersect
        lines << "- pair `#{pair_id}` (`#{en['query']}` vs `#{de['query']}`): #{intersect}/#{en_ids.size} overlap"
      end
      lines << ""
      lines << "**Aggregate overlap:** #{pct(total_overlap, total)}"
      lines << ""
      lines
    end

    def edge_case_section
      edges = results.select { |r| r["category"] == "edge_cases" }
      return [] if edges.empty?
      lines = ["## Edge-case behavior", ""]
      edges.each do |r|
        q = r["query"].to_s
        q_disp = q.empty? ? "(empty string)" : q.inspect
        smart = r["smart"] || {}
        if smart["skipped"]
          lines << "- #{q_disp} → skipped: #{smart['reason']}"
        elsif smart["success"] == false
          lines << "- #{q_disp} → failed: status=#{smart['status']}"
        else
          rec_count = (smart["recommendations"] || []).size
          lines << "- #{q_disp} → #{rec_count} picks, summary: #{smart['summary'].to_s[0, 80]}…"
        end
      end
      lines << ""
      lines
    end

    # ---- Utilities -------------------------------------------------------

    def percentile(sorted, p)
      return nil if sorted.empty?
      k = ((p / 100.0) * (sorted.length - 1)).round.clamp(0, sorted.length - 1)
      sorted[k]
    end

    def pct(num, denom)
      return "0%" if denom.to_i.zero?
      "#{(100.0 * num / denom).round(1)}%"
    end

    # symbol-or-string indifferent dig
    def dig(hash, *keys)
      return nil unless hash.is_a?(Hash)
      keys.reduce(hash) do |acc, k|
        next nil unless acc.is_a?(Hash)
        acc[k] || acc[k.to_sym] || acc[k.to_s]
      end
    end
  end
end
