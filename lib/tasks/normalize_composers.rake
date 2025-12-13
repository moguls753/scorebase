# frozen_string_literal: true

require "net/http"
require "json"

namespace :normalize do
  desc "Normalize composers using Gemini AI (LIMIT=100 for testing)"
  task composers: :environment do
    api_key = ENV["GEMINI_API_KEY"]
    abort "Set GEMINI_API_KEY" if api_key.blank?

    # Load IMSLP for inline validation
    imslp_file = Rails.root.join("db", "canonical_composers_imslp.txt")
    imslp_set = File.exist?(imslp_file) ? Set.new(File.readlines(imslp_file, chomp: true)) : Set.new

    composers = Score.distinct.pluck(:composer).compact
    limit = ENV["LIMIT"]&.to_i
    composers = composers.first(limit) if limit&.positive?

    puts "#{composers.count} composers to normalize#{limit ? " (limited)" : ""}"
    puts "IMSLP list: #{imslp_set.size} composers loaded\n\n"

    mappings = {}
    matched_imslp = 0
    batch_size = 40

    composers.each_slice(batch_size).with_index do |batch, idx|
      puts "Batch #{idx + 1}/#{(composers.count / batch_size.to_f).ceil}"

      result = gemini_normalize(api_key, batch)
      result&.each do |item|
        normalized = item["normalized"]
        mappings[item["original"]] = normalized

        # Check IMSLP match
        in_imslp = normalized && imslp_set.include?(normalized)
        matched_imslp += 1 if in_imslp
        mark = in_imslp ? "✓" : " "

        puts "  #{mark} #{item['original'][0..32].ljust(35)} -> #{normalized}"
      end

      sleep 4 unless idx == (composers.count / batch_size.to_f).ceil - 1
    end

    # Summary
    puts "\n#{"=" * 50}"
    puts "Total: #{mappings.count}"
    puts "IMSLP matches: #{matched_imslp} (#{(matched_imslp * 100.0 / mappings.count).round(1)}%)"
    puts "No match: #{mappings.count { |_, v| v.nil? }}"

    # Save
    output = Rails.root.join("tmp", "composer_mappings_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json")
    File.write(output, JSON.pretty_generate(mappings))
    puts "\nSaved to: #{output}"
  end

  desc "Validate mappings against IMSLP list"
  task validate: :environment do
    file = ENV["FILE"]
    abort "Specify FILE=path/to/mappings.json" if file.blank?

    imslp = File.readlines(Rails.root.join("db", "canonical_composers_imslp.txt"), chomp: true)
    imslp_set = Set.new(imslp)
    imslp_downcase = imslp.map { |c| [c.downcase, c] }.to_h

    mappings = JSON.parse(File.read(file))

    matched = 0
    unmatched = []

    mappings.each do |orig, norm|
      if imslp_set.include?(norm) || imslp_downcase[norm&.downcase]
        matched += 1
      else
        unmatched << [orig, norm]
      end
    end

    puts "Matched to IMSLP: #{matched}/#{mappings.count}"
    puts "\nUnmatched (#{unmatched.count}):"
    unmatched.first(30).each { |o, n| puts "  #{o[0..30]} -> #{n}" }
  end

  desc "Apply mappings"
  task apply: :environment do
    file = ENV["FILE"]
    abort "Specify FILE=path/to/mappings.json" if file.blank?

    mappings = JSON.parse(File.read(file))
    count = 0

    mappings.each do |original, normalized|
      next unless normalized
      updated = Score.where(composer: original).update_all(composer: normalized)
      count += updated
    end

    puts "Updated #{count} scores"
  end

  private

  def gemini_normalize(api_key, batch)
    uri = URI("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=#{api_key}")

    prompt = <<~PROMPT
      Normalize these composer names to "LastName, FirstName" format (standard music library format).

      Rules:
      - "J.S. Bach" -> "Bach, Johann Sebastian"
      - "Mozart" -> "Mozart, Wolfgang Amadeus"
      - "Arr. by X" -> return the arranger name normalized
      - Garbage like "Op. 25" or key signatures -> return null
      - Unknown -> return null

      Input: #{batch.to_json}

      Return JSON: [{"original": "input", "normalized": "LastName, FirstName" or null}]
    PROMPT

    body = {
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: { responseMimeType: "application/json", temperature: 0.1 }
    }

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.read_timeout = 60

    # Fix for certificate CRL errors on some systems
    http.verify_callback = ->(_ok, _ctx) { true }

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req.body = body.to_json

    res = http.request(req)

    unless res.code == "200"
      puts "  API Error #{res.code}: #{res.body[0..200]}"
      return nil
    end

    body = JSON.parse(res.body)
    text = body.dig("candidates", 0, "content", "parts", 0, "text")

    unless text
      puts "  No text in response: #{body.keys}"
      return nil
    end

    JSON.parse(text)
  rescue => e
    puts "  Error: #{e.class} - #{e.message}"
    nil
  end
end
