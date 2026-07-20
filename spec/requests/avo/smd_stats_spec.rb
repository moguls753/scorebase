require "rails_helper"

RSpec.describe "Avo SMD stats", type: :request do
  let(:admin_user) { "admin" }
  let(:admin_password) { "test-secret" }

  # CI runs without RAILS_MASTER_KEY, so real credentials are unreadable and Avo's
  # authenticate_with would raise. Stub the two lookups it makes.
  before do
    credentials = Rails.application.credentials
    allow(credentials).to receive(:dig).and_call_original
    allow(credentials).to receive(:dig).with(:basic_auth, :user).and_return(admin_user)
    allow(credentials).to receive(:dig).with(:basic_auth, :password).and_return(admin_password)
  end

  def get_smd_stats
    get "/admin/smd_stats", headers: {
      "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(
        admin_user, admin_password
      )
    }
  end

  # The headline conversion card, by its markup, so the assertion can't drift onto
  # another number on the page.
  def headline_rate
    response.body[%r{text-2xl font-bold text-violet-600">([^<]*)<}, 1]&.strip
  end

  it "reports the conversion rate from converting visits, not from click events" do
    create(:daily_stat, date: Date.current, visits: 100, converting_visits: 6,
                        smd_clicks_by_score: { "1" => 40 })

    get_smd_stats

    expect(response).to have_http_status(:ok)
    expect(headline_rate).to eq("6.0%")
  end

  it "ignores rows without converting_visits on both sides of the rate" do
    create(:daily_stat, date: Date.current, visits: 100, converting_visits: 6)
    create(:daily_stat, date: Date.current - 5, visits: 900, converting_visits: nil,
                        smd_clicks_by_score: { "1" => 500 })

    get_smd_stats

    expect(headline_rate).to eq("6.0%")
  end

  it "renders an em-dash when no row in the window has been aggregated yet" do
    create(:daily_stat, date: Date.current, visits: 500, converting_visits: nil)

    get_smd_stats

    expect(headline_rate).to eq("—")
  end

  it "does not divide by zero on an empty window" do
    get_smd_stats

    expect(response).to have_http_status(:ok)
    expect(headline_rate).to eq("—")
  end
end
