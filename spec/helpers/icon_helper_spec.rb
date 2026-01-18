# frozen_string_literal: true

require "rails_helper"

RSpec.describe IconHelper, type: :helper do
  it "loads icons from YAML" do
    expect(IconHelper::ICONS[:instruments][:piano]).to include("<path")
    expect(IconHelper::ICONS[:periods][:baroque]).to include("<path")
    expect(IconHelper::ICONS[:genres][:jazz]).to include("<path")
    expect(IconHelper::ICONS[:navigation][:composers]).to include("<circle")
  end

  it "renders instrument icons with fallback" do
    expect(helper.instrument_svg_icon("piano")).to include("<svg")
    expect(helper.instrument_svg_icon("unknown")).to include("<svg")
    expect(helper.instrument_svg_icon(nil)).to include("<svg")
  end

  it "renders period icons with fallback" do
    expect(helper.period_svg_icon("Baroque")).to include("<svg")
    expect(helper.period_svg_icon("unknown")).to include("<svg")
  end

  it "renders genre icons with fallback" do
    expect(helper.genre_svg_icon("Jazz")).to include("<svg")
    expect(helper.genre_svg_icon("unknown")).to include("<svg")
  end

  it "renders navigation icons" do
    %i[composers genres instruments periods].each do |cat|
      expect(helper.navigation_svg_icon(cat)).to include("<svg")
    end
  end

  it "resolves instrument patterns" do
    expect(helper.instrument_svg_icon("Alto Saxophone")).to include(IconHelper::ICONS[:instruments][:saxophone].strip)
    expect(helper.instrument_svg_icon("Electric Guitar")).to include(IconHelper::ICONS[:instruments][:guitar].strip)
  end
end
