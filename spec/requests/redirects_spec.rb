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
