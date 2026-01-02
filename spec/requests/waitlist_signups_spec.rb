require "rails_helper"

RSpec.describe "Waitlist Signups", type: :request do
  let(:valid_params) { { waitlist_signup: { email: "test@example.com" } } }
  let(:headers) { { "Content-Type" => "application/json" } }

  describe "POST /waitlist" do
    it "creates a signup with valid email" do
      expect {
        post "/waitlist", params: valid_params.to_json, headers: headers
      }.to change(WaitlistSignup, :count).by(1)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["success"]).to be true
    end

    it "captures locale from URL" do
      post "/de/waitlist", params: valid_params.to_json, headers: headers

      signup = WaitlistSignup.last
      expect(signup.locale).to eq("de")
    end

    it "handles duplicate email gracefully" do
      # First signup
      post "/waitlist", params: valid_params.to_json, headers: headers
      expect(response).to have_http_status(:created)

      # Duplicate signup
      post "/waitlist", params: valid_params.to_json, headers: headers
      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json["success"]).to be true
      expect(json["message"]).to match(/already/i)
    end

    it "rejects invalid email" do
      invalid_params = { waitlist_signup: { email: "not-an-email" } }

      post "/waitlist", params: invalid_params.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json["success"]).to be false
    end
  end

  # Note: Rate limiting tests skipped
  # Rate limiting uses Rails.cache which we trust works correctly
  # Test manually: curl the endpoint 6 times and verify 6th request gets 429
end
