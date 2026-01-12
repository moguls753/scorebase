# frozen_string_literal: true

namespace :normalize do
  desc "Infer pedagogical grades using LLM. LIMIT=100, BACKEND=groq (free), or openai MODEL=gpt-4o (84% accuracy)"
  task pedagogical_grades: :environment do
    limit = ENV.fetch("LIMIT", 100).to_i
    backend = ENV.fetch("BACKEND", "groq").to_sym
    model = ENV["MODEL"]  # Optional: gpt-4o for better accuracy
    batch_size = ENV.fetch("BATCH_SIZE", 5).to_i

    NormalizePedagogicalGradeJob.perform_now(limit: limit, backend: backend, model: model, batch_size: batch_size)
    print_grade_stats
  end

  desc "Reset pedagogical grade normalization. SCOPE=all|failed"
  task reset_pedagogical_grades: :environment do
    scope = ENV.fetch("SCOPE", "failed")

    count = case scope
    when "all"
      Score.where.not(grade_status: "pending").update_all(
        grade_status: "pending",
        pedagogical_grade: nil,
        pedagogical_grade_de: nil,
        grade_source: nil
      )
    when "failed"
      Score.grade_failed.update_all(grade_status: "pending")
    else
      abort "Unknown scope: #{scope}. Use SCOPE=all or SCOPE=failed"
    end

    puts "Reset #{count} scores to grade_status=pending"
  end

  def print_grade_stats
    puts
    puts "Pedagogical grade stats:"
    puts "  Normalized:     #{Score.grade_normalized.count}"
    puts "  Not applicable: #{Score.grade_not_applicable.count}"
    puts "  Failed:         #{Score.grade_failed.count}"
    puts "  Pending:        #{Score.grade_pending.count}"

    # Show grade distribution
    puts
    puts "Grade distribution:"
    Score.grade_normalized.group(:pedagogical_grade).count.sort_by { |_, v| -v }.first(10).each do |grade, count|
      puts "  #{grade}: #{count}"
    end
  end
end
