namespace :pdfs do
  desc "Sync PDFs from IMSLP to Active Storage (R2)"
  task sync: :environment do
    batch_size = ENV.fetch("BATCH_SIZE", 100).to_i
    delay_ms = ENV.fetch("DELAY_MS", 500).to_i  # Rate limiting - be gentle with IMSLP

    # Only IMSLP scores with pdf_path that don't have synced pdf_file yet
    # NOTE: CPDL is blocked by Cloudflare, skip for now
    scope = Score.from_imslp
                 .where.not(pdf_path: [nil, "", "N/A"])
                 .left_joins(:pdf_file_attachment)
                 .where(active_storage_attachments: { id: nil })

    total = scope.count
    puts "Syncing #{total} IMSLP PDFs..."
    puts "Batch size: #{batch_size}, Delay: #{delay_ms}ms"
    puts

    processed = 0
    success = 0
    failed = 0
    start_time = Time.current

    scope.find_each(batch_size: batch_size) do |score|
      syncer = PdfSyncer.new(score)
      if syncer.sync
        success += 1
        print "."
      else
        failed += 1
        print "X"
        puts " Failed ##{score.id}: #{syncer.errors.join(', ')}" if syncer.errors.any?
      end

      processed += 1
      sleep(delay_ms / 1000.0) if delay_ms > 0

      if processed % 100 == 0
        elapsed = Time.current - start_time
        rate = processed / elapsed
        eta = (total - processed) / rate
        puts
        puts "[#{processed}/#{total}] #{success} ok, #{failed} failed | #{rate.round(1)}/s | ETA: #{(eta / 60).round(1)} min"
      end
    end

    elapsed = Time.current - start_time
    puts
    puts
    puts "Done in #{(elapsed / 60).round(1)} minutes"
    puts "Success: #{success}, Failed: #{failed}"
  end

  desc "Sync PDFs from CPDL to Active Storage (R2) - requires manual Cloudflare bypass"
  task sync_cpdl: :environment do
    puts "CPDL is protected by Cloudflare. Manual intervention required."
    puts "Run this after you've set up Cloudflare bypass."
    puts

    scope = Score.from_cpdl
                 .where.not(pdf_path: [nil, "", "N/A"])
                 .left_joins(:pdf_file_attachment)
                 .where(active_storage_attachments: { id: nil })

    total = scope.count
    puts "#{total} CPDL PDFs pending sync"

    # Same logic as sync task but for CPDL
    # Uncomment when Cloudflare bypass is ready:
    #
    # scope.find_each do |score|
    #   syncer = PdfSyncer.new(score)
    #   result = syncer.sync
    #   puts "#{result ? 'OK' : 'FAIL'} ##{score.id}"
    # end
  end

  desc "Show PDF sync stats"
  task stats: :environment do
    puts "PDF Sync Stats"
    puts "--------------"

    Score::SOURCES.each do |src|
      total = Score.where(source: src).where.not(pdf_path: [nil, "", "N/A"]).count
      synced = Score.where(source: src).joins(:pdf_file_attachment).count
      pending = total - synced

      puts "#{src.upcase}:"
      puts "  Total with PDF: #{total}"
      puts "  Synced to R2:   #{synced}"
      puts "  Pending:        #{pending}"
      puts
    end

    # Storage estimate
    synced_count = Score.joins(:pdf_file_attachment).count
    if synced_count > 0
      sizes = ActiveStorage::Blob.joins(:attachments)
                                 .where(active_storage_attachments: { name: "pdf_file" })
                                 .limit(100)
                                 .pluck(:byte_size)
      if sizes.any?
        avg_mb = (sizes.sum / sizes.count.to_f / 1024 / 1024).round(2)
        total_synced_gb = (Score.joins(:pdf_file_attachment).count * avg_mb / 1024).round(2)
        puts "Storage (sampled):"
        puts "  Avg PDF size: #{avg_mb} MB"
        puts "  Total synced: ~#{total_synced_gb} GB"
      end
    end
  end
end
