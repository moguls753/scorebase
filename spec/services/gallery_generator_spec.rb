# frozen_string_literal: true

require "rails_helper"

RSpec.describe GalleryGenerator do
  describe "#generate" do
    it "skips if gallery already exists" do
      score = create(:score, pdf_path: "test.pdf")
      score.score_pages.create!(page_number: 1)

      result = described_class.new(score).generate

      expect(result).to be true
      expect(score.score_pages.count).to eq(1) # unchanged
    end

    it "returns false if no PDF" do
      score = create(:score, pdf_path: nil)

      result = described_class.new(score).generate

      expect(result).to be false
    end
  end
end
