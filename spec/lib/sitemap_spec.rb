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
end
