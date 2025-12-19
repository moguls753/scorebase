# frozen_string_literal: true

require "rails_helper"

RSpec.describe ThumbnailGenerator do
  let(:score) { create(:score, :pdmx, thumbnail_url: "https://example.com/thumb.png") }
  let(:generator) { described_class.new(score) }

  describe "#generate" do
    context "when thumbnail already attached" do
      before do
        score.thumbnail_image.attach(
          io: StringIO.new("fake image"),
          filename: "test.webp",
          content_type: "image/webp"
        )
      end

      it "returns true and skips generation" do
        expect(generator.generate).to be true
        expect(generator.errors).to be_empty
      end
    end

    context "when no thumbnail_url present" do
      let(:score) { create(:score, :pdmx, thumbnail_url: nil) }

      it "returns false" do
        expect(generator.generate).to be false
      end
    end

    context "when thumbnail_url is valid" do
      before do
        stub_request(:get, "https://example.com/thumb.png")
          .to_return(status: 200, body: "fake png data", headers: { "Content-Type" => "image/png" })

        # Mock ImageMagick convert command
        allow(generator).to receive(:system) do |*args|
          if args.first == "convert"
            # Create a fake webp file at the output path
            output_path = args[-2]
            File.write(output_path, "fake webp data")
            true
          end
        end
      end

      it "downloads image and creates attachment" do
        expect(generator.generate).to be true
        expect(score.thumbnail_image).to be_attached
        expect(score.thumbnail_image.filename.to_s).to eq("#{score.id}.webp")
      end
    end

    context "when download fails" do
      before do
        stub_request(:get, "https://example.com/thumb.png")
          .to_return(status: 404, body: "Not Found")
      end

      it "returns false" do
        expect(generator.generate).to be false
      end
    end
  end
end
