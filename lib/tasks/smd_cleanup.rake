# frozen_string_literal: true

namespace :smd do
  desc "Decode escaped characters in SMD score titles (one-time cleanup)"
  task decode_titles: :environment do
    require "cgi"
    require "json"

    # Fix encoding issues in a string:
    # 1. Mojibake (UTF-8 read as Latin-1): Ã§ → ç
    # 2. JSON unicode escapes: \u0027 → '
    # 3. HTML entities: &#39; → '
    fix_encoding = ->(str) {
      return str if str.blank?

      result = str.dup

      # Fix mojibake: if string has Ã followed by another char, it's likely UTF-8 misread as Latin-1
      if result.match?(/Ã[£§©®°±²³µ¶·¸¹º»¼½¾¿À-ÿ]/)
        result = result.encode("ISO-8859-1", "UTF-8", invalid: :replace, undef: :replace)
                       .force_encoding("UTF-8") rescue result
      end

      # Decode JSON/Unicode escapes (\u0027 → ')
      result = JSON.parse(%("#{result}")) rescue result

      # Decode HTML entities (&#39; → ')
      CGI.unescapeHTML(result)
    }

    # Find SMD scores with encoding issues
    candidates = Score.where(source: "smd")
      .where("title LIKE '%\\u00%' OR clean_title LIKE '%\\u00%' OR composer LIKE '%\\u00%' " \
             "OR title LIKE '%&#%' OR clean_title LIKE '%&#%' OR composer LIKE '%&#%' " \
             "OR title LIKE '%Ã%' OR clean_title LIKE '%Ã%' OR composer LIKE '%Ã%'")

    puts "Found #{candidates.count} SMD scores needing cleanup"

    candidates.find_each do |score|
      score.update_columns(
        title: fix_encoding.call(score.title),
        clean_title: fix_encoding.call(score.clean_title),
        composer: fix_encoding.call(score.composer)
      )
      print "."
    end

    puts "\nDone!"
  end
end
