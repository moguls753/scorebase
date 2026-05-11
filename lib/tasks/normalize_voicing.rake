# frozen_string_literal: true

namespace :normalize do
  desc "Extract voicing and instruments for vocal scores. LIMIT=100, BACKEND=openai|groq|gemini|lmstudio. Requires: has_vocal=true"
  task voicing: :environment do
    limit = ENV.fetch("LIMIT", 100).to_i
    backend = ENV.fetch("BACKEND", "openai").to_sym

    NormalizeVoicingJob.perform_now(limit: limit, backend: backend)
    print_voicing_stats
  end

  desc "Reset voicing normalization. SCOPE=all|failed"
  task reset_voicing: :environment do
    scope = ENV.fetch("SCOPE", "failed")

    count = case scope
    when "all"
      # Reset both voicing and instruments since the job sets both
      Score.where.not(voicing_status: "pending").update_all(
        voicing_status: "pending",
        voicing: nil,
        instruments: nil
      )
    when "failed"
      Score.voicing_failed.update_all(voicing_status: "pending")
    else
      abort "Unknown scope: #{scope}. Use SCOPE=all or SCOPE=failed"
    end

    puts "Reset #{count} scores to voicing_status=pending"
  end

  desc "Mark vocal scores without part_names as not_applicable for voicing"
  task mark_voicing_not_applicable: :environment do
    count = Score.voicing_pending
                 .has_vocal_normalized
                 .where(has_vocal: true)
                 .where(part_names: [nil, ""])
                 .update_all(voicing_status: "not_applicable")

    puts "Marked #{count} scores as voicing_status=not_applicable (no part_names)"
  end

  desc "Backfill voicing_status=normalized from raw CPDL scraper voicing field. " \
       "Only touches rows the LLM voicing job won't process (no part_names). " \
       "Strips CPDL wiki-template suffix (|add=...) and alternative-edition comma form (',...'). " \
       "ENV: DRY_RUN=true|false (default true), " \
       "INCLUDE_LLM_ELIGIBLE=true|false (default false — set true to also backfill rows with part_names)"
  task backfill_voicing: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    include_llm_eligible = ENV.fetch("INCLUDE_LLM_ELIGIBLE", "false") == "true"

    scope = Score
              .where(source: "cpdl")
              .voicing_pending
              .where.not(voicing: [nil, ""])
              .where("substr(trim(voicing), 1, 1) NOT IN ('|', ',')")

    scope = scope.where(part_names: [nil, ""]) unless include_llm_eligible

    total = scope.count
    with_pipe = scope.where("voicing LIKE ?", "%|%").count
    with_comma = scope.where("voicing LIKE ?", "%,%").count

    puts "Voicing backfill plan (CPDL only)"
    puts "  Total candidates:        #{total}"
    puts "  Will strip '|...' tail:  #{with_pipe}"
    puts "  Will strip ',...' tail:  #{with_comma}"

    if total.zero?
      puts
      puts "Nothing to do."
      next
    end

    if dry_run
      puts
      puts "DRY_RUN=true — no changes written. Re-run with DRY_RUN=false to apply."
      next
    end

    puts
    puts "Applying..."

    # Map verified-deterministic raw forms to LLM-canonical "SoloX" form.
    solo_map = {
      "S" => "SoloS", "Solo S" => "SoloS", "Solo Soprano" => "SoloS",
      "A" => "SoloA", "Solo A" => "SoloA", "Solo Alto"    => "SoloA",
      "T" => "SoloT", "Solo T" => "SoloT", "Solo Tenor"   => "SoloT",
      "B" => "SoloB", "Solo B" => "SoloB", "Solo Bass"    => "SoloB"
    }.freeze

    updated = 0
    canonicalized = 0
    Score.transaction do
      scope.find_each(batch_size: 1000) do |s|
        raw = s.voicing.split(/[|,]/).first.to_s.strip
        next if raw.empty?
        cleaned = solo_map.fetch(raw, raw)
        canonicalized += 1 if cleaned != raw
        s.update_columns(voicing: cleaned, voicing_status: "normalized")
        updated += 1
      end
    end

    puts "Updated #{updated} rows (#{canonicalized} mapped to SoloX canonical form)"
    puts
    puts "CPDL voicing after backfill:"
    puts "  normalized: #{Score.where(source: 'cpdl', voicing_status: 'normalized').count}"
    puts "  pending:    #{Score.where(source: 'cpdl', voicing_status: 'pending').count}"
  end

  def print_voicing_stats
    puts
    puts "Voicing normalization:"
    puts "  Normalized:     #{Score.voicing_normalized.count}"
    puts "  Not applicable: #{Score.voicing_not_applicable.count}"
    puts "  Failed:         #{Score.voicing_failed.count}"
    puts "  Pending:        #{Score.voicing_pending.count}"
    puts
    puts "Eligible (has_vocal=true, voicing_pending):"
    puts "  #{Score.voicing_pending.has_vocal_normalized.where(has_vocal: true).count}"
  end
end
