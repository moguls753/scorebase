require 'rails_helper'

RSpec.describe "SMD Redirects", type: :request do
  describe "GET /go/smd/:smd_id" do
    it "redirects to SMD with affiliate tag" do
      get "/go/smd/437132", headers: { "HTTP_REFERER" => "https://www.example.com/scores/123" }

      expect(response).to have_http_status(:found)
      expect(response.location).to eq("https://www.sheetmusicdirect.com/se/ID_No/437132/Product.aspx?affiliate=67428")
    end

    it "never persists the full internal referrer URL on the visit" do
      Score.create!(external_id: "437132", source: "smd", title: "Test")

      get "/go/smd/437132", headers: {
        "HTTP_REFERER"    => "https://www.example.com/scores/123?q=secret",
        "HTTP_USER_AGENT" => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36"
      }

      visit = Ahoy::Visit.last
      expect(visit.referrer).to be_nil
      expect(visit.referring_domain).to eq("example.com")
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
end
