# frozen_string_literal: true

require "rails_helper"

RSpec.describe IconHelper, type: :helper do
  describe "ICONS constant" do
    it "loads instruments from YAML" do
      expect(IconHelper::ICONS[:instruments]).to be_a(Hash)
      expect(IconHelper::ICONS[:instruments][:piano]).to include("<path")
    end

    it "loads periods from YAML" do
      expect(IconHelper::ICONS[:periods]).to be_a(Hash)
      expect(IconHelper::ICONS[:periods][:baroque]).to include("<path")
    end

    it "loads genres from YAML" do
      expect(IconHelper::ICONS[:genres]).to be_a(Hash)
      expect(IconHelper::ICONS[:genres][:jazz]).to include("<path")
    end
  end

  describe "#instrument_svg_icon" do
    it "renders an SVG for a known instrument" do
      result = helper.instrument_svg_icon("piano")

      expect(result).to include("<svg")
      expect(result).to include('viewBox="0 0 20 20"')
      expect(result).to include('aria-hidden="true"')
    end

    it "defaults to orchestra icon for unknown instruments" do
      result = helper.instrument_svg_icon("theremin")

      expect(result).to include(IconHelper::ICONS[:instruments][:orchestra].strip)
    end

    it "handles nil gracefully" do
      result = helper.instrument_svg_icon(nil)

      expect(result).to include("<svg")
    end

    it "respects the size parameter" do
      result = helper.instrument_svg_icon("piano", size: 32)

      expect(result).to include('width="32"')
      expect(result).to include('height="32"')
    end

    it "includes custom CSS class when provided" do
      result = helper.instrument_svg_icon("piano", html_class: "my-custom-class")

      expect(result).to include('class="my-custom-class"')
    end

    it "omits class attribute when no class provided" do
      result = helper.instrument_svg_icon("piano")

      expect(result).not_to include("class=")
    end

    context "instrument name resolution" do
      {
        "Piano" => :piano,
        "VIOLIN" => :violin,
        "String Quartet" => :violin,
        "Mezzo-soprano" => :voice,
        "A Cappella Choir" => :voice,
        "Electric Guitar" => :guitar,
        "Double Bass" => :double_bass,
        "Contrabass" => :double_bass,
        "Snare Drum" => :drums,
        "Alto Saxophone" => :saxophone
      }.each do |input, expected_key|
        it "resolves '#{input}' to :#{expected_key}" do
          result = helper.instrument_svg_icon(input)
          expected_svg = IconHelper::ICONS[:instruments][expected_key]

          expect(result).to include(expected_svg.strip)
        end
      end
    end
  end

  describe "#period_svg_icon" do
    it "renders an SVG for a known period" do
      result = helper.period_svg_icon("Baroque")

      expect(result).to include("<svg")
      expect(result).to include(IconHelper::ICONS[:periods][:baroque].strip)
    end

    it "defaults to classical for unknown periods" do
      result = helper.period_svg_icon("Unknown Era")

      expect(result).to include(IconHelper::ICONS[:periods][:classical].strip)
    end

    it "handles nil gracefully" do
      result = helper.period_svg_icon(nil)

      expect(result).to include(IconHelper::ICONS[:periods][:classical].strip)
    end

    context "period name resolution" do
      {
        "Medieval" => :medieval,
        "Renaissance" => :renaissance,
        "Baroque" => :baroque,
        "Classical" => :classical,
        "Romantic" => :romantic,
        "Impressionist" => :impressionist,
        "Modern" => :modern,
        "20th Century" => :modern,
        "Contemporary" => :modern
      }.each do |input, expected_key|
        it "resolves '#{input}' to :#{expected_key}" do
          result = helper.period_svg_icon(input)
          expected_svg = IconHelper::ICONS[:periods][expected_key]

          expect(result).to include(expected_svg.strip)
        end
      end
    end
  end

  describe "#genre_svg_icon" do
    it "renders an SVG for a known genre" do
      result = helper.genre_svg_icon("Jazz")

      expect(result).to include("<svg")
      expect(result).to include(IconHelper::ICONS[:genres][:jazz].strip)
    end

    it "defaults to default icon for unknown genres" do
      result = helper.genre_svg_icon("Experimental Noise")

      expect(result).to include(IconHelper::ICONS[:genres][:default].strip)
    end

    it "uses period icons for classical/baroque/romantic genres" do
      result = helper.genre_svg_icon("Classical")

      expect(result).to include(IconHelper::ICONS[:periods][:classical].strip)
    end

    context "genre name resolution" do
      {
        "Classical" => :classical,
        "Baroque" => :baroque,
        "Romantic" => :romantic,
        "Sacred Music" => :sacred,
        "Religious" => :sacred,
        "Choral" => :sacred,
        "Jazz" => :jazz,
        "Folk" => :folk,
        "Traditional" => :folk,
        "Opera" => :opera,
        "Aria" => :opera,
        "March" => :march,
        "Military" => :march,
        "Dance" => :dance,
        "Waltz" => :dance,
        "Tango" => :dance
      }.each do |input, expected_key|
        it "resolves '#{input}' to :#{expected_key}" do
          result = helper.genre_svg_icon(input)
          # Genre can come from either genres or periods
          expected_svg = IconHelper::ICONS[:genres][expected_key] || IconHelper::ICONS[:periods][expected_key]

          expect(result).to include(expected_svg.strip)
        end
      end
    end
  end
end
