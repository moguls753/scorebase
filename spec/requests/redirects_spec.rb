require 'rails_helper'

RSpec.describe "SMD Redirects", type: :request do
  describe "GET /go/smd/:smd_id" do
    it "redirects to SMD with affiliate tag" do
      get "/go/smd/437132", headers: { "HTTP_REFERER" => "https://www.example.com/scores/123" }

      expect(response).to have_http_status(:found)
      expect(response.location).to eq("https://www.sheetmusicdirect.com/se/ID_No/437132/Product.aspx?affiliate=67428")
    end

    it "does not track an SMD click server-side (the click is tracked client-side on the real button click)" do
      expect do
        get "/go/smd/437132", headers: { "HTTP_REFERER" => "https://www.example.com/scores/123" }
      end.not_to change { Ahoy::Event.where(name: "SMD click").count }

      expect(response).to have_http_status(:found)
    end

    it "rejects non-numeric IDs" do
      get "/go/smd/abc"
      expect(response).to have_http_status(:bad_request)
    end

    it "rejects requests without a referrer" do
      get "/go/smd/437132"
      expect(response).to have_http_status(:forbidden)
    end

    it "rejects requests with an external referrer" do
      get "/go/smd/437132", headers: { "HTTP_REFERER" => "https://evil.com/page" }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /go/stretta/:id" do
    let(:internal) { { "HTTP_REFERER" => "https://www.example.com/scores/123" } }
    let!(:score) do
      create(:score, source: "stretta", external_id: "148059",
                     partner_slug: "leitner-grosser-gott-wir-loben-dich-nr-148059")
    end

    # Measured against the live shop: /x-nr-<id>.html answers 301 to the slug URL and
    # drops the query string with it, so that form earns nothing. Only the slug form
    # keeps ?afl=. Settlement is half-yearly, so the loss would surface in February.
    it "redirects to the canonical slug URL carrying the affiliate parameter" do
      get "/go/stretta/148059", headers: internal

      expect(response).to have_http_status(:found)
      expect(response.location).to eq(
        "https://www.stretta-music.de/leitner-grosser-gott-wir-loben-dich-nr-148059.html" \
        "?afl=#{Score::STRETTA_AFFILIATE_ID}"
      )
      expect(response.location).not_to include("x-nr-")
    end

    it "does not track the click server-side" do
      expect do
        get "/go/stretta/148059", headers: internal
      end.not_to change { Ahoy::Event.where(name: "Stretta click").count }
    end

    it "rejects non-numeric IDs" do
      get "/go/stretta/abc", headers: internal
      expect(response).to have_http_status(:bad_request)
    end

    it "rejects requests without a referrer" do
      get "/go/stretta/148059"
      expect(response).to have_http_status(:forbidden)
    end

    it "rejects requests with an external referrer" do
      get "/go/stretta/148059", headers: { "HTTP_REFERER" => "https://evil.com/page" }
      expect(response).to have_http_status(:forbidden)
    end

    it "404s for an unknown product rather than guessing a URL" do
      get "/go/stretta/999999999", headers: internal
      expect(response).to have_http_status(:not_found)
    end

    it "404s when the stored slug is not a plain slug" do
      score.update_column(:partner_slug, "../evil")

      get "/go/stretta/148059", headers: internal

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /en/*path" do
    it "strips the /en prefix" do
      get "/en/scores/123"
      expect(response).to redirect_to("http://www.example.com/scores/123")
    end

    it "does not redirect to an attacker host smuggled in as an encoded leading slash" do
      get "/en/%2Fevil.example.com/x"
      expect(response).to redirect_to("http://www.example.com/evil.example.com/x")
    end
  end
end
