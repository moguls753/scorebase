require "rails_helper"

RSpec.describe "Avo affiliate stats", type: :request do
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

  def admin_get(path)
    get path, headers: {
      "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(
        admin_user, admin_password
      )
    }
  end

  def get_affiliate_stats
    admin_get "/admin/affiliate_stats"
  end

  # The headline conversion card, by its markup, so the assertion can't drift onto
  # another number on the page.
  def headline_rate
    response.body[%r{text-2xl font-bold text-violet-600">([^<]*)<}, 1]&.strip
  end

  def headline_human_visits
    response.body[%r{text-2xl font-bold text-green-600">([^<]*)<}, 1]&.strip
  end

  it "divides converting visits by visits that reached a paid page, not by all traffic" do
    create(:daily_stat, date: Date.current, human_visits: 1000, smd_page_visits: 200,
                        human_converting_visits: 6, smd_clicks_by_score: { "1" => 40 })

    get_affiliate_stats

    expect(response).to have_http_status(:ok)
    expect(headline_rate).to eq("3.0%")
  end

  it "renders an em-dash when the window has no measured rows" do
    create(:daily_stat, date: Date.current, human_visits: nil, human_converting_visits: nil)

    get_affiliate_stats

    expect(response).to have_http_status(:ok)
    expect(headline_rate).to eq("—")
  end

  it "reports the same human visit total as the analytics dashboard" do
    create(:daily_stat, date: Date.current, human_visits: 100, smd_page_visits: 20)
    create(:daily_stat, date: Date.current - 20, human_visits: 50, smd_page_visits: 10)

    get_affiliate_stats
    expect(headline_human_visits).to eq("150")

    admin_get "/admin/analytics"
    expect(response.body).to include("150 over 2d")
  end

  it "shows SMD and Stretta funnels separately" do
    create(:daily_stat, date: Date.current, human_visits: 1000,
                        partner_page_visits: { "smd" => 200, "stretta" => 80 },
                        partner_converting_visits: { "smd" => 6, "stretta" => 4 },
                        partner_clicks_by_score: { "smd" => { "1" => 6 }, "stretta" => { "2" => 4 } })

    get_affiliate_stats

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Sheet Music Direct")
    expect(response.body).to include("Stretta Music")
  end

  it "labels the daily clicks table with a column per partner" do
    create(:daily_stat, date: Date.current, human_visits: 1000,
                        partner_page_visits: { "smd" => 200, "stretta" => 80 },
                        partner_clicks_by_score: { "smd" => { "1" => 6 }, "stretta" => { "2" => 4 } })

    get_affiliate_stats

    expect(response.body).to include("Sheet Music Direct Clicks")
    expect(response.body).to include("Stretta Music Clicks")
  end
end
