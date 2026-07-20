require "rails_helper"

RSpec.describe "Ahoy tracking", type: :request do
  let(:headers) do
    { "HTTP_USER_AGENT" => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36" }
  end

  # ahoy.js sends events via sendBeacon as multipart `events_json`, not a JSON body.
  def track_view(properties)
    events = [{ name: "$view", properties: properties, time: Time.current.iso8601, id: SecureRandom.uuid }]
    post "/_internal/events", params: { events_json: events.to_json }, headers: headers
  end

  # Cloudflare's CF-Device-Type says "mobile"; device_detector says "smartphone".
  # Only the latter was mapped, so every phone was silently bucketed as desktop.
  {
    "mobile" => "mobile", "tablet" => "tablet", "desktop" => "desktop"
  }.each do |cf_value, expected|
    it "buckets Cloudflare's #{cf_value.inspect} device header as #{expected}" do
      track_view({ "page" => "/" }.tap { headers["HTTP_CF_DEVICE_TYPE"] = cf_value })

      expect(Ahoy::Visit.last.device_type).to eq(expected)
    end
  end

  it "records the browser-supplied hostname as the visit's referring_domain" do
    expect { track_view("page" => "/scores/1", "referring_domain" => "google.com") }
      .to change { Ahoy::Visit.count }.by(1)

    expect(Ahoy::Visit.last.referring_domain).to eq("google.com")
  end

  it "normalizes a www-prefixed hostname" do
    track_view("page" => "/", "referring_domain" => "www.google.com")

    expect(Ahoy::Visit.last.referring_domain).to eq("google.com")
  end

  it "never persists a full referrer URL or landing page" do
    track_view("page" => "/", "referring_domain" => "google.com")

    visit = Ahoy::Visit.last
    expect(visit.referrer).to be_nil
    expect(visit.landing_page).to be_nil
    expect(visit.ip).to be_nil
  end

  it "keeps the hostname out of the persisted event properties" do
    track_view("page" => "/scores/1", "referring_domain" => "google.com")

    expect(Ahoy::Event.last.properties).to eq("page" => "/scores/1")
  end

  it "leaves referring_domain nil when there is no referrer" do
    track_view("page" => "/")

    expect(Ahoy::Visit.last.referring_domain).to be_nil
  end

  it "ignores a garbage referring_domain without failing the request" do
    track_view("page" => "/", "referring_domain" => "https://evil.com/search?q=secret token")

    expect(response).to have_http_status(:ok)
    visit = Ahoy::Visit.last
    expect(visit.referring_domain).to be_nil
    expect(visit.referrer).to be_nil
  end

  it "records an internal referral as scorebase.org so DailyStat can exclude it" do
    track_view("page" => "/scores/1", "referring_domain" => "scorebase.org")

    DailyStat.aggregate_for!(Date.current)

    stat = DailyStat.find_by!(date: Date.current)
    expect(Ahoy::Visit.last.referring_domain).to eq("scorebase.org")
    expect(stat.visits).to eq(0)
    expect(stat.referrers).to eq({})
  end
end
