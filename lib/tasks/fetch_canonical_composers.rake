# frozen_string_literal: true

require "net/http"
require "json"

namespace :composers do
  desc "Fetch canonical composer list from IMSLP and verify uniqueness"
  task fetch_imslp: :environment do
    composers = []
    start = 0
    batch_size = 1000

    puts "Fetching composers from IMSLP..."

    loop do
      url = "https://imslp.org/imslpscripts/API.ISCR.php?account=worklist/disclaimer=accepted/sort=id/type=1/start=#{start}/retformat=json"
      uri = URI(url)

      response = Net::HTTP.get(uri)
      data = JSON.parse(response)

      # Extract composer names (keys that are numeric)
      batch = data.select { |k, _| k.match?(/^\d+$/) }.values.map do |entry|
        # Format: "Category:LastName, FirstName" -> "FirstName LastName"
        raw = entry["id"].to_s.sub("Category:", "")
        raw
      end

      break if batch.empty?

      composers.concat(batch)
      puts "  Fetched #{composers.count} composers (start=#{start})"

      # Check if more results available (inside metadata)
      break unless data.dig("metadata", "moreresultsavailable")

      start += batch_size
      sleep 0.5 # Be nice to IMSLP
    end

    puts "\nTotal fetched: #{composers.count}"

    # Check uniqueness
    unique_composers = composers.uniq
    puts "Unique composers: #{unique_composers.count}"

    if composers.count != unique_composers.count
      duplicates = composers.group_by(&:itself).select { |_, v| v.count > 1 }.keys
      puts "\nWARNING: Found #{duplicates.count} duplicates:"
      duplicates.first(20).each { |d| puts "  - #{d}" }
    else
      puts "✓ All composers are unique!"
    end

    # Check for similar names (potential duplicates)
    puts "\nChecking for similar names..."
    normalized = unique_composers.map { |c| [c, c.downcase.gsub(/[^a-z]/, "")] }
    grouped = normalized.group_by(&:last).select { |_, v| v.count > 1 }

    if grouped.any?
      puts "Found #{grouped.count} potential duplicates (same normalized form):"
      grouped.first(20).each do |_, names|
        puts "  - #{names.map(&:first).join(' | ')}"
      end
    else
      puts "✓ No obvious duplicates found!"
    end

    # Save to file
    output_file = Rails.root.join("db", "canonical_composers_imslp.txt")
    File.write(output_file, unique_composers.sort.join("\n"))
    puts "\nSaved #{unique_composers.count} composers to #{output_file}"
  end

  desc "Verify canonical composer list uniqueness"
  task verify: :environment do
    file = Rails.root.join("db", "canonical_composers_imslp.txt")
    abort "File not found: #{file}" unless File.exist?(file)

    composers = File.readlines(file, chomp: true)
    puts "Total entries: #{composers.count}"
    puts "Unique entries: #{composers.uniq.count}"

    # Check normalized uniqueness
    normalized = composers.map { |c| [c, c.downcase.gsub(/[^a-z]/, "")] }
    grouped = normalized.group_by(&:last).select { |_, v| v.count > 1 }

    if grouped.any?
      puts "\nPotential duplicates (#{grouped.count}):"
      grouped.each do |_, names|
        puts "  #{names.map(&:first).join(' | ')}"
      end
    else
      puts "✓ No duplicates found!"
    end
  end
end
