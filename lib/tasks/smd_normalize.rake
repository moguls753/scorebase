# frozen_string_literal: true

namespace :smd do
  namespace :normalize do
    desc "Enqueue SmdStatusNormalizer for vision-extracted SMD scores. Usage: rake smd:normalize:status LIMIT=5000"
    task status: :environment do
      limit = ENV.fetch("LIMIT", "5000").to_i

      ids = Score.where(source: "smd", deleted_at: nil)
                 .where(extraction_status: "vision_extracted")
                 .where(has_vocal_status: "pending")
                 .order(:id)
                 .limit(limit)
                 .pluck(:id)

      ids.each { |id| SmdNormalizeStatusJob.perform_later(id) }
      puts "Enqueued #{ids.size} SmdNormalizeStatusJob(s) (limit was #{limit})"
    end

    desc "Show SMD normalization progress"
    task stats: :environment do
      smd = Score.where(source: "smd", deleted_at: nil)
      total = smd.count
      with_vision = smd.where(extraction_status: "vision_extracted").count
      done = smd.where.not(has_vocal_status: "pending").count
      vocal = smd.where(has_vocal: true).count
      voicing = smd.where.not(voicing: [nil, ""]).count
      grade = smd.where.not(pedagogical_grade: nil).count
      genre = smd.where.not(genre: [nil, ""]).count

      pct = total.positive? ? (done.to_f / total * 100).round(1) : 0.0

      puts "SMD status normalization:"
      puts "  Active SMD scores:    #{total}"
      puts "  Vision-extracted:     #{with_vision}"
      puts "  Normalized:           #{done} (#{pct}%)"
      puts "  has_vocal=true:       #{vocal}"
      puts "  voicing filled:       #{voicing}"
      puts "  pedagogical_grade:    #{grade}"
      puts "  genre filled:         #{genre}"
    end
  end
end
