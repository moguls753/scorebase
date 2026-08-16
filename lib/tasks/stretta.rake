# frozen_string_literal: true

# Local-only tasks over the full sighting. The selection list they produce is a
# repo artifact (docs/stretta-import-plan.md §15); Kamal builds the image from the
# repo, so it reaches the container without a copy step or a network dependency.
#
# The list and the running filter share one implementation — Stretta::Classifier —
# rather than two copies of the same thresholds that drift apart.
namespace :stretta do
  SELECTION_DIR = "db/stretta"

  desc "Build db/stretta/selection-<date>.txt.gz from the local sighting (VENDORS='A|B' to restrict)"
  task selection: :environment do
    require "zlib"

    vendors = ENV["VENDORS"].to_s.split("|").map(&:strip).reject(&:empty?)
    reader = Stretta::SightingReader.new
    path = Rails.root.join(SELECTION_DIR, "selection-#{Date.current.iso8601}.txt.gz")
    FileUtils.mkdir_p(path.dirname)

    stats = Hash.new(0)
    handles = []
    reader.each_product(vendors: vendors) do |handle, product|
      result = Stretta::Classifier.classify(product)
      stats[result.reason] += 1
      handles << handle if result.accepted?
    end

    Zlib::GzipWriter.open(path) do |gz|
      gz.puts "# generated #{Time.current.iso8601} from #{Stretta::SightingReader::DEFAULT_PATH} (#{reader.count} rows)"
      gz.puts "# criterion Stretta::Classifier, itemtype lists config/stretta_itemtypes.json"
      gz.puts "# vendors #{vendors.any? ? vendors.join(', ') : 'all'}"
      gz.puts "# accepted #{handles.size}"
      handles.each { |handle| gz.puts handle }
    end

    puts "#{path} — #{handles.size} handles"
    stats.sort_by { |_, n| -n }.each { |reason, n| puts "  #{reason.to_s.ljust(32)} #{n}" }
  end

  desc "Import handles from a selection list (LIST=path, LIMIT=n)"
  task import: :environment do
    require "zlib"

    path = ENV["LIST"] || Dir[Rails.root.join(SELECTION_DIR, "selection-*.txt.gz")].max
    abort "no selection list found in #{SELECTION_DIR}" unless path

    handles = Zlib::GzipReader.open(path) { |gz| gz.each_line.reject { |l| l.start_with?("#") }.map(&:strip) }
    handles = handles.first(ENV["LIMIT"].to_i) if ENV["LIMIT"].to_i.positive?

    puts "importing #{handles.size} handles from #{File.basename(path)}"
    regroup = ENV["REGROUP"].present?
    report StrettaImportJob.new.perform(handles, regroup: regroup)
    next unless regroup

    # A new group key moves rows between groups; the visible one has to be picked again.
    BackfillGroupKeysJob.new.assign_representatives
    puts "representatives: #{Score.where(source: 'stretta', is_group_representative: true).count}"
  end

  def report(stats)
    puts stats.sort_by { |_, count| -count }.map { |reason, count| "#{reason}=#{count}" }.join(" ")
  end
end
