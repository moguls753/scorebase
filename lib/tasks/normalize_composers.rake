# frozen_string_literal: true

require "net/http"
require "json"

namespace :normalize do
  desc "Normalize composers using Gemini AI (LIMIT=100 for testing)"
  task composers: :environment do
    api_key = ENV["GEMINI_API_KEY"]
    abort "Set GEMINI_API_KEY" if api_key.blank?

    scores = Score.select(:id, :composer, :title, :editor, :genres, :language)
                  .distinct
                  .pluck(:composer, :title, :editor, :genres, :language)
                  .uniq { |row| row[0] } # unique by composer field

    limit = ENV["LIMIT"]&.to_i
    scores = scores.first(limit) if limit&.positive?

    puts "#{scores.count} unique composer fields to normalize#{limit ? " (limited)" : ""}\n\n"

    # Resume support (shared cache with IMSLP importer)
    output = Rails.root.join("tmp", "composer_normalizer_cache.json")
    mappings = File.exist?(output) ? JSON.parse(File.read(output)) : {}
    puts "Resuming with #{mappings.count} existing mappings\n" if mappings.any?

    # Filter already processed
    remaining = scores.reject { |row| mappings.key?(row[0]) }
    puts "Remaining: #{remaining.count} composers\n\n"

    batch_size = 40
    remaining.each_slice(batch_size).with_index do |batch, idx|
      puts "Batch #{idx + 1}/#{(remaining.count / batch_size.to_f).ceil}"

      result = gemini_normalize(api_key, batch)

      if result == :quota_exceeded
        puts "\n⚠️  Quota exceeded! Progress saved. Run again tomorrow."
        break
      end

      result&.each do |item|
        original = item["original"]
        normalized = item["normalized"]
        mappings[original] = normalized

        # Apply immediately
        if normalized
          updated = Score.where(composer: original).update_all(composer: normalized)
          puts "  [#{updated}] #{original[0..30].ljust(33)} -> #{normalized}"
        else
          puts "       #{original[0..30].ljust(33)} -> (unknown)"
        end
      end

      # Save progress after each batch
      File.write(output, JSON.pretty_generate(mappings))

      sleep 4 unless idx == (remaining.count / batch_size.to_f).ceil - 1
    end

    # Summary
    puts "\n#{"=" * 50}"
    puts "Total processed: #{mappings.count}"
    puts "Normalized & applied: #{mappings.count { |_, v| v }}"
    puts "Unknown (unchanged): #{mappings.count { |_, v| v.nil? }}"
    puts "\nProgress saved to: #{output}"
    puts "Run again to continue if quota was exceeded."
  end

  desc "Reset normalization cache"
  task reset: :environment do
    file = Rails.root.join("tmp", "composer_normalizer_cache.json")
    if File.exist?(file)
      File.delete(file)
      puts "Progress reset."
    else
      puts "No progress file found."
    end
  end


  private

  def gemini_normalize(api_key, batch)
    uri = URI("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=#{api_key}")

    # Format batch with context
    scores_data = batch.map do |composer, title, editor, genres, language|
      { composer: composer, title: title, editor: editor, genres: genres, language: language }
    end

    prompt = <<~PROMPT
      Identify the COMPOSER for each music score. Return normalized as "LastName, FirstName".

      Use ALL fields to identify the composer:
      - composer field may contain the composer, arranger, piece title, or garbage
      - title often contains composer name (e.g., "Sonata by Mozart")
      - editor might be the arranger (original composer may be famous)
      - genres/language can hint at likely composers

      Rules:
      - Use the composer's ORIGINAL native language name, not anglicized versions
      - German composer -> German name: "Händel, Georg Friedrich" (not "Handel, George Frideric")
      - "J.S. Bach" -> "Bach, Johann Sebastian"
      - "Mozart" -> "Mozart, Wolfgang Amadeus"
      - "Handel" -> "Händel, Georg Friedrich"
      - "Tchaikovsky" -> "Чайковский, Пётр Ильич" or "Tschaikowski, Pjotr Iljitsch" (use Latin script)
      - If composer field is garbage but title hints at composer -> extract it
      - Traditional/folk music with no known composer -> null
      - If truly unknown -> null

      Input: #{scores_data.to_json}

      Return JSON: [{"original": "composer field value", "normalized": "LastName, FirstName" or null}]
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

    if res.code == "429"
      puts "  Rate limited (429)"
      return :quota_exceeded
    end

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
