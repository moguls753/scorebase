# frozen_string_literal: true

namespace :pdfs do
  desc "Show PDF sync stats and progress"
  task stats: :environment do
    puts "=" * 60
    puts "PDF Sync Stats"
    puts "=" * 60

    %w[imslp cpdl].each do |src|
      total = Score.where(source: src).where.not(pdf_path: [nil, "", "N/A"]).count
      synced = Score.where(source: src).joins(:pdf_file_attachment).count
      remaining = total - synced
      pct = total > 0 ? (synced.to_f / total * 100).round(1) : 0

      puts
      puts "#{src.upcase}"
      puts "-" * 40
      puts "  Total with PDF URL:  #{total}"
      puts "  Synced to R2:        #{synced}"
      puts "  Remaining:           #{remaining}"
      puts "  Progress:            #{pct}%"
    end

    puts
    puts "=" * 60

    # Show queue status if solid_queue available
    if defined?(SolidQueue::Job)
      pending = SolidQueue::Job.where(class_name: "SyncPdfJob").count
      puts "Queued SyncPdfJob:     #{pending}"
      puts "=" * 60
    end
  end

  desc "Watch PDF sync progress (refreshes every 5 seconds)"
  task watch: :environment do
    loop do
      system("clear") || system("cls")
      Rake::Task["pdfs:stats"].execute
      puts
      puts "Watching... (Ctrl+C to stop)"
      sleep 5
    end
  end
end
