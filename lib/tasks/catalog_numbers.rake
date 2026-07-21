namespace :scores do
  desc "Backfill catalog_number on IMSLP scores from external_url (DRY_RUN=1 to preview)"
  task backfill_catalog_numbers: :environment do
    dry_run = ENV["DRY_RUN"].present?
    scope = Score.where(source: "imslp", catalog_number: nil)

    total = scope.count
    updated = 0
    samples = []

    scope.find_each(batch_size: 1000) do |score|
      catalog = CatalogNumberExtractor.extract(score.title, score.external_url)
      next if catalog.blank?

      updated += 1
      samples << "#{score.title} -> #{catalog}" if samples.size < 20
      score.update_column(:catalog_number, catalog) unless dry_run
    end

    puts "Scanned #{total} IMSLP rows without a catalog_number."
    puts "#{dry_run ? 'Would extract' : 'Extracted'} #{updated} catalog numbers."
    puts "Sample:" if samples.any?
    samples.each { |s| puts "  #{s}" }
  end
end
