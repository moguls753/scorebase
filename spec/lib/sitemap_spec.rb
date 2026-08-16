# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sitemap generation" do
  # Threshold from sitemap.rb
  let(:threshold) { 10 }

  before do
    # Clear any existing scores
    Score.delete_all
  end

  describe "genre pages" do
    it "uses the genre field (not genres) for counting" do
      # Create scores with genres that meet threshold
      threshold.times { create(:score, genre: "Sacred") }
      (threshold - 1).times { create(:score, genre: "Jazz") }

      genre_counts = Hash.new(0)
      Score.where.not(genre: [nil, ""]).pluck(:genre).each do |genre_str|
        genre_str.split("-").map(&:strip).reject(&:blank?).each do |genre|
          genre_counts[genre] += 1
        end
      end

      qualifying = genre_counts.select { |_, count| count >= threshold }

      expect(qualifying.keys).to include("Sacred")
      expect(qualifying.keys).not_to include("Jazz")
    end

    it "handles hyphen-delimited genre strings" do
      threshold.times { create(:score, genre: "Sacred-Baroque music") }

      genre_counts = Hash.new(0)
      Score.where.not(genre: [nil, ""]).pluck(:genre).each do |genre_str|
        genre_str.split("-").map(&:strip).reject(&:blank?).each do |genre|
          genre_counts[genre] += 1
        end
      end

      expect(genre_counts["Sacred"]).to eq(threshold)
      expect(genre_counts["Baroque music"]).to eq(threshold)
    end
  end

  describe "composer pages" do
    it "groups composers by slug and aggregates counts" do
      # Same composer, different casing
      6.times { create(:score, composer: "Bach, Johann Sebastian") }
      5.times { create(:score, composer: "BACH, JOHANN SEBASTIAN") }

      composer_counts = Score.where.not(composer: [nil, ""])
                             .group(:composer)
                             .count

      by_slug = Hash.new { |h, k| h[k] = { names: [], total: 0 } }
      composer_counts.each do |name, count|
        slug = name.parameterize
        by_slug[slug][:names] << name
        by_slug[slug][:total] += count
      end

      # Both should aggregate under same slug
      bach_data = by_slug["bach-johann-sebastian"]
      expect(bach_data[:total]).to eq(11)
      expect(bach_data[:names].size).to eq(2)
    end
  end

  describe "genre + instrument combinations" do
    it "finds instruments for scores matching a genre" do
      threshold.times { create(:score, genre: "Classical", instruments: "Piano") }
      5.times { create(:score, genre: "Jazz", instruments: "Saxophone") }

      # Simulates sitemap logic for genre + instrument combinations
      instrument_for_genre = Hash.new(0)
      Score.where("genre LIKE ?", "%#{Score.sanitize_sql_like('Classical')}%")
           .where.not(instruments: [nil, ""])
           .pluck(:instruments).each do |instruments_str|
        instruments_str.split(/[;,]/).map(&:strip).reject(&:blank?).each do |instrument|
          normalized = instrument.gsub(/\s*\(.*\)/, "").strip.downcase
          instrument_for_genre[normalized] += 1
        end
      end

      expect(instrument_for_genre["piano"]).to eq(threshold)
      expect(instrument_for_genre["saxophone"]).to eq(0) # Jazz scores not included
    end

    it "handles multi-value instrument strings" do
      threshold.times { create(:score, genre: "Baroque", instruments: "Violin; Cello") }

      instrument_for_genre = Hash.new(0)
      Score.where("genre LIKE ?", "%Baroque%")
           .where.not(instruments: [nil, ""])
           .pluck(:instruments).each do |instruments_str|
        instruments_str.split(/[;,]/).map(&:strip).reject(&:blank?).each do |instrument|
          normalized = instrument.gsub(/\s*\(.*\)/, "").strip.downcase
          instrument_for_genre[normalized] += 1
        end
      end

      expect(instrument_for_genre["violin"]).to eq(threshold)
      expect(instrument_for_genre["cello"]).to eq(threshold)
    end
  end

  describe "SMD representative pages" do
    it "includes representatives and excludes members, ungrouped, and free scores" do
      rep = create(:score, :smd, group_key: "g", is_group_representative: true)
      member = create(:score, :smd, group_key: "g", is_group_representative: false)
      ungrouped = create(:score, :smd, group_key: nil)
      free = create(:score, source: "pdmx")

      reps = Score.active.smd_group_representatives

      expect(reps).to include(rep)
      expect(reps).not_to include(member, ungrouped, free)
    end

    # All 254,329 Stretta representatives would be half a million URLs across two
    # locales, most of them linked from nowhere. Only the internally reachable ones
    # are submitted: on an ensemble hub, or in a free score's buy box.
    describe "Stretta pages" do
      let(:free) { create(:score, :pdmx) }

      it "includes a representative that sits on an ensemble hub" do
        page = create(:score, :stretta, is_group_representative: true, smd_category: "Concert Band")

        expect(Score.active.stretta_sitemap_pages).to include(page)
      end

      it "includes a representative linked from a free score" do
        page = create(:score, :stretta, is_group_representative: true)
        ScoreStrettaMatch.create!(score: free, stretta_score: page, rank: 1)

        expect(Score.active.stretta_sitemap_pages).to include(page)
      end

      it "excludes an orphan, a hidden member and an unsellable row" do
        orphan = create(:score, :stretta, is_group_representative: true)
        member = create(:score, :stretta, is_group_representative: nil, smd_category: "Concert Band")
        gone = create(:score, :stretta, is_group_representative: true,
                                        smd_category: "Concert Band", available_for_sale: false)

        expect(Score.active.stretta_sitemap_pages).not_to include(orphan, member, gone)
      end

      it "stays out of the SMD representative scope" do
        page = create(:score, :stretta, is_group_representative: true)

        expect(Score.active.smd_group_representatives).not_to include(page)
      end
    end

    # Runs the real config/sitemap.rb end-to-end. Regression guard: a positional
    # score_path(score) binds to the optional (:locale) route segment, not :id.
    it "emits each representative's URL in both locales" do
      rep = create(:score, :smd, is_group_representative: true, title: "Sitemap Rep")

      expect { SitemapGenerator::Interpreter.run(verbose: false) }.not_to raise_error

      xml = Zlib::GzipReader.open(Rails.root.join("storage/sitemaps/sitemap.xml.gz"), &:read)
      expect(xml).to include("/scores/#{rep.id}</loc>")
      expect(xml).to include("/de/scores/#{rep.id}</loc>")
    end
  end

  describe "ensemble hub pages" do
    it "emits a threshold-meeting ensemble hub URL in both locales" do
      threshold.times { create(:score, :smd, smd_category: "Concert Band") }

      expect { SitemapGenerator::Interpreter.run(verbose: false) }.not_to raise_error

      xml = Zlib::GzipReader.open(Rails.root.join("storage/sitemaps/sitemap.xml.gz"), &:read)
      expect(xml).to include("/ensembles/concert-band</loc>")
      expect(xml).to include("/de/ensembles/concert-band</loc>")
      expect(xml).to include("/ensembles</loc>")
    end
  end

  describe "combination hub pages" do
    def generated_xml
      SitemapGenerator::Interpreter.run(verbose: false)
      Zlib::GzipReader.open(Rails.root.join("storage/sitemaps/sitemap.xml.gz"), &:read)
    end

    it "sums period variants for period + instrument combinations" do
      7.times { create(:score, period: "Romantic", instruments: "Piano") }
      5.times { create(:score, period: "19th Century", instruments: "Piano") }

      expect(generated_xml).to include("/periods/romantic/piano</loc>")
    end

    it "sums genre case variants for genre + instrument combinations" do
      5.times { create(:score, genre: "Motet", genre_status: "normalized", instruments: "Piano") }
      5.times { create(:score, genre: "motet", genre_status: "normalized", instruments: "Piano") }

      expect(generated_xml).to include("/genres/motet/piano</loc>")
    end

    it "counts only normalized genres in genre + instrument combinations" do
      9.times { create(:score, genre: "Motet", genre_status: "normalized", instruments: "Piano") }
      5.times { create(:score, genre: "Motet", genre_status: "pending", instruments: "Piano") }
      create(:score, genre: "Motet", genre_status: "normalized", instruments: "Violin")

      xml = generated_xml
      expect(xml).to include("/genres/motet</loc>")
      expect(xml).not_to include("/genres/motet/piano</loc>")
    end

    it "keeps composer case twins as separate counts" do
      ComposerMapping.create!(original_name: "Anonymous", normalized_name: "Anonymous")
      ComposerMapping.create!(original_name: "anonymous.", normalized_name: "anonymous")
      10.times { create(:score, composer: "Anonymous", instruments: "Piano") }
      6.times { create(:score, composer: "anonymous", instruments: "Piano") }
      4.times { create(:score, composer: "anonymous", instruments: nil) }

      # Only the "Anonymous" twin reaches threshold with piano: en + de, not four.
      expect(generated_xml.scan("/composers/anonymous/piano</loc>").size).to eq(2)
    end

    it "does not let decoy instruments inflate a composer + instrument combination" do
      ComposerMapping.create!(original_name: "J.S. Bach", normalized_name: "Bach, Johann Sebastian")
      9.times { create(:score, composer: "Bach, Johann Sebastian", instruments: "Horn") }
      3.times { create(:score, composer: "Bach, Johann Sebastian", instruments: "English Horn") }
      2.times { create(:score, composer: "Handel, George Frideric", instruments: "Horn") }

      xml = generated_xml
      expect(xml).to include("/instruments/horn</loc>")
      expect(xml).not_to include("/composers/bach-johann-sebastian/horn</loc>")
    end
  end
end
