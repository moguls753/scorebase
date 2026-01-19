# frozen_string_literal: true

require "rails_helper"

RSpec.describe IconHelper, type: :helper do
  describe "#navigation_svg_icon" do
    it "renders navigation icons" do
      expect(helper.navigation_svg_icon(:composers)).to include("<svg")
      expect(helper.navigation_svg_icon(:periods, size: 24)).to include('width="24"')
    end
  end

  describe "#period_svg_icon" do
    it "renders period icons with pattern matching" do
      expect(helper.period_svg_icon("baroque")).to include("<svg")
    end

    it "falls back to classical for unknown periods" do
      expect(helper.period_svg_icon("unknown")).to eq(helper.period_svg_icon("classical"))
    end
  end
end
