# frozen_string_literal: true

namespace :smd do
  namespace :vision do
    desc "Enqueue vision extraction jobs for unprocessed SMD scores. Usage: rake smd:vision:enqueue LIMIT=500"
    task enqueue: :environment do
      limit = ENV.fetch("LIMIT", "1000").to_i

      ids = Score.where(source: "smd", deleted_at: nil)
                 .where.not(preview_image_url: [nil, ""])
                 .where(extraction_status: "pending")
                 .order(:id)
                 .limit(limit)
                 .pluck(:id)

      ids.each { |id| SmdVisionExtractJob.perform_later(id) }
      puts "Enqueued #{ids.size} SmdVisionExtractJob(s) (limit was #{limit})"
    end

    desc "Show vision extraction progress"
    task stats: :environment do
      smd = Score.where(source: "smd", deleted_at: nil)
      total = smd.count
      with_preview = smd.where.not(preview_image_url: [nil, ""]).count
      done = smd.where(extraction_status: "vision_extracted").count
      pending = with_preview - done

      pct = total.positive? ? (done.to_f / total * 100).round(1) : 0.0

      puts "SMD vision extraction:"
      puts "  Active SMD scores:         #{total}"
      puts "  Have preview_image_url:    #{with_preview}"
      puts "  Vision-processed:          #{done} (#{pct}%)"
      puts "  Pending (have preview):    #{pending}"
    end
  end
end
