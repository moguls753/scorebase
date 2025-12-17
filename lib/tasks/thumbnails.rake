namespace :thumbnails do
  desc "Cache thumbnails from external URLs to local WebP (PDMX + IMSLP)"
  task cache: :environment do
    batch_size = ENV.fetch("BATCH_SIZE", 100).to_i
    delay_ms = ENV.fetch("DELAY_MS", 50).to_i  # Rate limiting between requests

    # Only scores with thumbnail_url that don't have cached thumbnail yet
    scope = Score.where.not(thumbnail_url: [nil, ""])
                 .left_joins(:thumbnail_image_attachment)
                 .where(active_storage_attachments: { id: nil })

    total = scope.count
    puts "Caching #{total} thumbnails..."
    puts "Batch size: #{batch_size}, Delay: #{delay_ms}ms"
    puts

    processed = 0
    success = 0
    failed = 0
    start_time = Time.current

    scope.find_each(batch_size: batch_size) do |score|
      gen = ThumbnailGenerator.new(score)
      if gen.generate
        success += 1
      else
        failed += 1
        puts "  Failed ##{score.id}: #{gen.errors.join(', ')}" if gen.errors.any?
      end

      processed += 1
      sleep(delay_ms / 1000.0) if delay_ms > 0

      # Progress every 100
      if processed % 100 == 0
        elapsed = Time.current - start_time
        rate = processed / elapsed
        eta = (total - processed) / rate
        puts "[#{processed}/#{total}] #{success} ok, #{failed} failed | #{rate.round(1)}/s | ETA: #{(eta / 60).round(1)} min"
      end
    end

    elapsed = Time.current - start_time
    puts
    puts "Done in #{(elapsed / 60).round(1)} minutes"
    puts "Success: #{success}, Failed: #{failed}"
  end

  desc "Show thumbnail cache stats"
  task stats: :environment do
    total = Score.count
    with_url = Score.where.not(thumbnail_url: [nil, ""]).count
    cached = Score.joins(:thumbnail_image_attachment).count

    puts "Thumbnail Stats"
    puts "---------------"
    puts "Total scores:     #{total}"
    puts "With external URL: #{with_url}"
    puts "Cached locally:   #{cached}"
    puts "Remaining:        #{with_url - cached}"
    puts
    puts "By source:"
    Score::SOURCES.each do |src|
      src_total = Score.where(source: src).count
      src_cached = Score.where(source: src).joins(:thumbnail_image_attachment).count
      puts "  #{src.upcase}: #{src_cached}/#{src_total} cached"
    end

    if cached > 0
      # Sample file sizes
      sizes = ActiveStorage::Blob.joins(:attachments)
                                 .where(active_storage_attachments: { name: "thumbnail_image" })
                                 .limit(1000)
                                 .pluck(:byte_size)
      avg_kb = (sizes.sum / sizes.count.to_f / 1024).round(2)
      total_mb = (sizes.sum / 1024.0 / 1024).round(2)
      estimated_gb = (avg_kb * with_url / 1024 / 1024).round(2)

      puts
      puts "Storage (sampled from #{sizes.count} thumbnails):"
      puts "  Avg size: #{avg_kb} KB"
      puts "  Sample total: #{total_mb} MB"
      puts "  Estimated full cache: #{estimated_gb} GB"
    end
  end

  desc "Clear all cached thumbnails"
  task clear: :environment do
    count = Score.joins(:thumbnail_image_attachment).count
    print "This will delete #{count} cached thumbnails. Continue? [y/N] "
    confirm = $stdin.gets.chomp.downcase
    if confirm == "y"
      Score.find_each do |score|
        score.thumbnail_image.purge if score.thumbnail_image.attached?
      end
      puts "Cleared all cached thumbnails."
    else
      puts "Aborted."
    end
  end
end
