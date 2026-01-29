# frozen_string_literal: true

namespace :smd do
  desc "Decode escaped characters in SMD score titles (one-time cleanup)"
  task decode_titles: :environment do
    require "cgi"
    require "json"

    # Decode JSON unicode escapes (\u0027) and HTML entities (&#39;)
    decode = ->(str) {
      return str if str.blank?
      decoded = JSON.parse(%("#{str}")) rescue str
      CGI.unescapeHTML(decoded)
    }

    # Find SMD scores with escaped characters (Unicode or HTML entities)
    candidates = Score.where(source: "smd")
      .where("title LIKE '%\\u00%' OR clean_title LIKE '%\\u00%' OR composer LIKE '%\\u00%' " \
             "OR title LIKE '%&#%' OR clean_title LIKE '%&#%' OR composer LIKE '%&#%'")

    puts "Found #{candidates.count} SMD scores needing cleanup"

    candidates.find_each do |score|
      score.update_columns(
        title: decode.call(score.title),
        clean_title: decode.call(score.clean_title),
        composer: decode.call(score.composer)
      )
      print "."
    end

    puts "\nDone!"
  end
end
