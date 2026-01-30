# frozen_string_literal: true

require "nokogiri"
require "json"
require "cgi"

module SmdCrawler
  class MetadataExtractor
    # Only map when SMD explicitly indicates difficulty
    # Unknown difficulty = nil (not embedded for semantic search)
    DIFFICULTY_MAP = [
      [/super\s*easy|very\s*easy/i, "beginner"],
      [/\beasy\b|e-z|beginning/i, "elementary"]
    ].freeze

    def extract(html)
      doc = Nokogiri::HTML(html, nil, "UTF-8")

      json_ld = extract_json_ld(doc)
      js_vars = extract_js_variables(doc)

      genres = js_vars["genres_list"] || []
      instruments_arr = json_ld.dig("additionalProperty", "value") || []
      tags = genres.join("-")
      first_contributor = decode_html(js_vars["artists_contributors_list"]&.first)

      {
        # Core identifiers (smd_id → external_id in Score)
        external_id: json_ld["mpn"]&.to_s,
        title: decode_html(json_ld["name"]),
        clean_title: decode_html(js_vars["title"]),

        # Artist/contributors
        # Klassik-tagged scores are classical → no artist (composer only)
        # Non-Klassik scores are modern → artist = performer/brand name
        composer: first_contributor,
        artist: klassik_tagged?(tags) ? nil : first_contributor,
        contributors: js_vars["artists_contributors_list"]&.map { |c| decode_html(c) }&.uniq,

        # Classification
        instruments: instruments_arr.join(", "),
        main_instrument: js_vars["main_instrument"],
        tags: tags,  # SMD genres → tags (hyphen-delimited)
        smd_category: js_vars["category_level_2"],
        arrangement_category: js_vars["arrangementCategory"],
        difficulty: map_difficulty(js_vars["category_level_2"]),

        # Publisher/source
        brand: json_ld["brand"],
        is_arrangeme: js_vars["is_arrangeme"] == "True",

        # Pricing
        price_usd: json_ld.dig("offers", "price")&.to_f,
        original_price_usd: js_vars["original_price"]&.to_f,

        # Rating
        rating: json_ld.dig("aggregateRating", "ratingValue")&.to_f,
        review_count: json_ld.dig("aggregateRating", "reviewCount")&.to_i,

        # Details
        page_count: extract_page_count(doc),
        pitch_range: extract_range(doc),
        is_interactive: js_vars["is_interactive"] == "True",

        # Images
        thumbnail_url: json_ld.dig("image", "thumbnail"),
        preview_image_url: json_ld.dig("image", "contentUrl"),

        # Source
        source: "smd"
      }
    end

    private

    def extract_json_ld(doc)
      script = doc.at_css('script[type="application/ld+json"]')
      return {} unless script

      data = JSON.parse(script.text)
      data = data.first if data.is_a?(Array)
      data.is_a?(Hash) ? data : {}
    rescue JSON::ParserError
      {}
    end

    def extract_js_variables(doc)
      vars = {}

      doc.css("script").each do |script|
        text = script.text

        # Arrays (JSON format)
        if (match = text.match(/"artists_contributors_list":\s*(\[[^\]]+\])/))
          vars["artists_contributors_list"] = JSON.parse(match[1]) rescue nil
        end

        if (match = text.match(/"genres_list":\s*(\[[^\]]+\])/))
          vars["genres_list"] = JSON.parse(match[1]) rescue nil
        end

        # Double-quoted strings
        {
          "category_level_2" => /"category_level_2":\s*"([^"]+)"/,
          "title" => /"title":\s*"([^"]+)"/,
          "main_instrument" => /"main_instrument":\s*"([^"]+)"/,
          "is_interactive" => /"is_interactive":\s*"([^"]+)"/,
          "is_arrangeme" => /"arrangeme":\s*"([^"]+)"/i
        }.each do |key, pattern|
          if (match = text.match(pattern))
            vars[key] ||= match[1]
          end
        end

        # Numbers
        if (match = text.match(/"original_price":\s*([\d.]+)/))
          vars["original_price"] = match[1]
        end

        # Single-quoted strings (JS object literals)
        if (match = text.match(/'arrangementCategory':\s*'([^']+)'/))
          vars["arrangementCategory"] = match[1]
        end

        if (match = text.match(/'isArrangeMe':\s*'([^']+)'/))
          vars["is_arrangeme"] ||= match[1]
        end
      end

      vars
    end

    def extract_page_count(doc)
      meta = doc.at_css('meta[name="twitter:data1"]')
      meta&.[]("content")&.to_i
    end

    def extract_range(doc)
      meta = doc.at_css('meta[name="twitter:data2"]')
      meta&.[]("content")
    end

    def map_difficulty(category)
      return nil if category.nil?

      DIFFICULTY_MAP.each do |pattern, difficulty|
        return difficulty if category.match?(pattern)
      end

      nil
    end

    # Classical music detection via SMD's Klassik genre tag
    # Klassik-tagged scores don't get artist field (use composer hub pages instead)
    def klassik_tagged?(tags)
      return false if tags.nil?
      tags.include?("Klassik")
    end

    # Decode escaped strings from JS/JSON sources
    # Handles: \u0027 → ', &#39; → ', &amp; → &, etc.
    def decode_html(str)
      return nil if str.nil?

      # First decode JSON/Unicode escapes (\u0027 → ')
      decoded = JSON.parse(%("#{str}")) rescue str

      # Then decode HTML entities (&#39; → ')
      CGI.unescapeHTML(decoded)
    end
  end
end
