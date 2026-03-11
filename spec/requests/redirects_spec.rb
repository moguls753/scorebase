require 'rails_helper'

RSpec.describe "SMD Redirects", type: :request do
  describe "GET /go/smd/:smd_id" do
    it "redirects to SMD with affiliate tag" do
      get "/go/smd/437132", headers: { "HTTP_REFERER" => "https://www.example.com/scores/123" }

      expect(response).to have_http_status(:found)
      expect(response.location).to eq("https://www.sheetmusicdirect.com/se/ID_No/437132/Product.aspx?affiliate=67428")
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
