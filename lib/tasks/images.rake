# frozen_string_literal: true

# Developer tools for image generation.
# Production batch processing is handled by recurring jobs (config/recurring.yml).
namespace :images do
  desc "Show image generation stats"
  task stats: :environment do
    puts "=" * 60
    puts "Image Generation Stats"
    puts "=" * 60

    total_scores = Score.count
    puts "Total scores: #{total_scores}"
    puts

    # Thumbnails
    puts "THUMBNAILS"
    puts "-" * 40
    with_url = Score.where.not(thumbnail_url: [nil, ""]).count
    cached = Score.joins(:thumbnail_image_attachment).count
    puts "  With external URL: #{with_url}"
    puts "  Cached to R2:      #{cached}"
    puts "  Remaining:         #{with_url - cached}"
    puts

    Score::SOURCES.each do |src|
      src_with_url = Score.where(source: src).where.not(thumbnail_url: [nil, ""]).count
      src_cached = Score.where(source: src).joins(:thumbnail_image_attachment).count
      pct = src_with_url > 0 ? (src_cached.to_f / src_with_url * 100).round(1) : 0
      puts "  #{src.upcase.ljust(6)}: #{src_cached}/#{src_with_url} (#{pct}%)"
    end
    puts

    # Gallery
    puts "GALLERY PAGES"
    puts "-" * 40
    with_pdf = Score.where.not(pdf_path: [nil, "", "N/A"]).count
    with_gallery = ScorePage.distinct.count(:score_id)
    total_pages = ScorePage.count
    puts "  Scores with PDF:     #{with_pdf}"
    puts "  Scores with gallery: #{with_gallery}"
    puts "  Total pages:         #{total_pages}"
    puts "  Remaining:           #{with_pdf - with_gallery}"
    puts

    Score::SOURCES.each do |src|
      src_with_pdf = Score.where(source: src).where.not(pdf_path: [nil, "", "N/A"]).count
      src_with_gallery = Score.where(source: src).joins(:score_pages).distinct.count
      pct = src_with_pdf > 0 ? (src_with_gallery.to_f / src_with_pdf * 100).round(1) : 0
      puts "  #{src.upcase.ljust(6)}: #{src_with_gallery}/#{src_with_pdf} (#{pct}%)"
    end
    puts

    # Storage estimates
    puts "STORAGE"
    puts "-" * 40
    thumbnail_sizes = ActiveStorage::Blob.joins(:attachments)
                                         .where(active_storage_attachments: { name: "thumbnail_image" })
                                         .limit(1000)
                                         .pluck(:byte_size)
    if thumbnail_sizes.any?
      avg_thumb_kb = (thumbnail_sizes.sum / thumbnail_sizes.count.to_f / 1024).round(1)
      est_thumb_gb = (avg_thumb_kb * with_url / 1024 / 1024).round(2)
      puts "  Thumbnails: avg #{avg_thumb_kb}KB, est. total #{est_thumb_gb}GB"
    end

    page_sizes = ActiveStorage::Blob.joins(:attachments)
                                    .where(active_storage_attachments: { name: "image", record_type: "ScorePage" })
                                    .limit(1000)
                                    .pluck(:byte_size)
    if page_sizes.any?
      avg_page_kb = (page_sizes.sum / page_sizes.count.to_f / 1024).round(1)
      avg_pages = Score.where.not(page_count: [nil, 0]).average(:page_count).to_f.round(1)
      avg_pages = 3.0 if avg_pages.zero?
      est_pages = with_pdf * avg_pages
      est_gallery_gb = (avg_page_kb * est_pages / 1024 / 1024).round(2)
      puts "  Gallery: avg #{avg_page_kb}KB/page, ~#{avg_pages} pages/score, est. total #{est_gallery_gb}GB"
    end

    puts "=" * 60
  end

  desc "Regenerate gallery for a specific score. Usage: images:regenerate[score_id]"
  task :regenerate, [:score_id] => :environment do |_t, args|
    score = Score.find(args[:score_id])
    puts "Regenerating gallery for Score ##{score.id}: #{score.title}"

    deleted = score.score_pages.destroy_all.size
    puts "Deleted #{deleted} existing pages"

    if score.generate_gallery
      puts "Success! Generated #{score.reload.score_pages.count} pages"
    else
      puts "Failed to generate gallery"
    end
  end
end
