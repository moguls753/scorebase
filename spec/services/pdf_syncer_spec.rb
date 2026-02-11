# frozen_string_literal: true

require "rails_helper"

RSpec.describe PdfSyncer do
  let(:syncer) { described_class.new(score) }

  describe "#sync" do
    context "when score is PDMX" do
      let(:score) { create(:score, :pdmx) }

      it "returns true and skips sync (PDMX has local files)" do
        expect(syncer.sync).to be true
        expect(score.pdf_file).not_to be_attached
      end
    end

    context "when pdf_file already attached" do
      let(:score) { create(:score, :imslp) }

      before do
        score.pdf_file.attach(
          io: StringIO.new("fake pdf"),
          filename: "test.pdf",
          content_type: "application/pdf"
        )
      end

      it "returns true and skips sync" do
        expect(syncer.sync).to be true
        expect(syncer.errors).to be_empty
      end
    end

    context "when no PDF available" do
      let(:score) { create(:score, :imslp, pdf_path: nil) }

      it "returns false" do
        expect(syncer.sync).to be false
      end
    end

    context "when IMSLP score with valid PDF" do
      let(:score) { create(:score, :imslp, pdf_path: "test.pdf", external_id: "12345") }
      let(:pdf_data) { "%PDF-1.4 fake pdf content" }
      let(:imslp_html) do
        '<span id="sm_dl_wait" data-id="https://s9.imslp.org/files/test/Bach_BWV565.pdf"></span>'
      end

      before do
        # IMSLP page is fetched via CloudflareBypass proxy (localhost:8000)
        stub_request(:get, /localhost:8000\/wiki\/Special:IMSLPImageHandler/)
          .to_return(status: 200, body: imslp_html, headers: { "Content-Type" => "text/html" })

        # CDN returns the actual PDF
        stub_request(:get, "https://s9.imslp.org/files/test/Bach_BWV565.pdf")
          .to_return(
            status: 200,
            body: pdf_data,
            headers: {
              "Content-Type" => "application/pdf",
              "Content-Disposition" => 'attachment; filename="Bach_BWV565.pdf"'
            }
          )
      end

      it "downloads PDF and creates attachment" do
        expect(syncer.sync).to be true
        expect(score.pdf_file).to be_attached
        expect(score.pdf_file.filename.to_s).to eq("Bach_BWV565.pdf")
        expect(score.pdf_file.content_type).to eq("application/pdf")
      end
    end

    context "when download fails" do
      let(:score) { create(:score, :imslp, pdf_path: "test.pdf", external_id: "12345") }

      before do
        stub_request(:get, /localhost:8000/)
          .to_return(status: 404, body: "Not Found")
      end

      it "returns false" do
        expect(syncer.sync).to be false
      end
    end
  end
end
