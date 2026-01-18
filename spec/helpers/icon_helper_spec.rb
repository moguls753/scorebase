# frozen_string_literal: true

require "rails_helper"

RSpec.describe IconHelper, type: :helper do
  it "renders navigation icons" do
    expect(helper.navigation_svg_icon(:composers)).to include("<svg")
    expect(helper.navigation_svg_icon(:periods, size: 24)).to include('width="24"')
  end

  it "renders period icons with fallback" do
    expect(helper.period_svg_icon("baroque")).to include("<svg")
    expect(helper.period_svg_icon("unknown")).to eq(helper.period_svg_icon("classical"))
  end

  it "renders genre icons with pattern matching" do
    expect(helper.genre_svg_icon("jazz")).to include("<svg")
    expect(helper.genre_svg_icon("Religious Music")).to eq(helper.genre_svg_icon("sacred"))
  end

  it "returns nil for deprecated instrument icons" do
    expect(helper.instrument_svg_icon("piano")).to be_nil
  end
end
