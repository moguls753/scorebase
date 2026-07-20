require 'rails_helper'

RSpec.describe DailyStat, type: :model do
  describe '.aggregate_for!' do
    let(:date) { Date.new(2026, 4, 15) }
    let(:noon) { date.in_time_zone.change(hour: 12) }

    def make_visit(**overrides)
      Ahoy::Visit.create!({
        started_at: noon,
        visit_token: SecureRandom.uuid,
        visitor_token: SecureRandom.uuid
      }.merge(overrides))
    end

    context 'when there is no Ahoy data for the date' do
      it 'does not create a DailyStat row' do
        expect { described_class.aggregate_for!(date) }.not_to change { DailyStat.count }
      end

      it 'does not overwrite a pre-existing legacy row' do
        legacy = DailyStat.create!(date: date, visits: 5000, countries: { "DE" => 5000 })
        described_class.aggregate_for!(date)
        legacy.reload
        expect(legacy.visits).to eq(5000)
        expect(legacy.countries).to eq("DE" => 5000)
      end
    end

    context 'with pageviews, visits, and SMD clicks' do
      before do
        v1 = make_visit(country: "DE", browser: "Chrome", device_type: "desktop",
                        referring_domain: "google.com", user_agent: "UA-1")
        v2 = make_visit(country: "US", browser: "Firefox", device_type: "mobile",
                        referring_domain: nil, user_agent: "UA-2")
        Ahoy::Event.create!(visit: v1, name: "$view", properties: { "page" => "/scores/1" }, time: noon)
        Ahoy::Event.create!(visit: v1, name: "$view", properties: { "page" => "/scores/1" }, time: noon)
        Ahoy::Event.create!(visit: v2, name: "$view", properties: { "page" => "/search" },   time: noon)
        Ahoy::Event.create!(visit: v1, name: "SMD click", properties: { "score_id" => 42 }, time: noon)
        Ahoy::Event.create!(visit: v1, name: "SMD click", properties: { "score_id" => 42 }, time: noon)
        Ahoy::Event.create!(visit: v2, name: "SMD click", properties: { "score_id" => 99 }, time: noon)
        Ahoy::Event.create!(visit: v1, name: "Cross-link visit", properties: { "score_id" => 42 }, time: noon)
        Ahoy::Event.create!(visit: v2, name: "Cross-link visit", properties: { "score_id" => 42 }, time: noon)
      end

      it 'aggregates into the dashboard JSON shape' do
        described_class.aggregate_for!(date)
        ds = DailyStat.find_by!(date: date)

        # `visits` counts external arrivals (visits = sessions), not pageviews.
        # v1 (google.com) and v2 (direct) are both external → 2 visits.
        expect(ds.visits).to eq(2)
        expect(ds.paths).to eq("/scores/1" => 2, "/search" => 1)
        expect(ds.countries).to eq("DE" => 1, "US" => 1)
        expect(ds.browsers).to eq("Chrome" => 1, "Firefox" => 1)
        expect(ds.devices).to eq("desktop" => 1, "mobile" => 1)
        expect(ds.referrers).to eq("google.com" => 1, "direct" => 1)
        expect(ds.user_agents).to eq("UA-1" => 1, "UA-2" => 1)
        expect(ds.smd_clicks_by_score).to eq("42" => 2, "99" => 1)
        expect(ds.cross_link_visits_by_score).to eq("42" => 2)
        # v1 clicked twice, v2 once: converting_visits counts visits, not events.
        expect(ds.converting_visits).to eq(2)
      end

      it 'is idempotent on repeat invocation' do
        described_class.aggregate_for!(date)
        snapshot = DailyStat.find_by(date: date).attributes.except("updated_at")
        described_class.aggregate_for!(date)
        expect(DailyStat.find_by(date: date).attributes.except("updated_at")).to eq(snapshot)
      end
    end

    context 'internal-referrer filtering' do
      it 'excludes internal-referrer visits from visits/countries/devices/referrers but keeps their pageviews and SMD clicks' do
        external = make_visit(country: "DE", browser: "Chrome", device_type: "desktop",
                              referring_domain: "google.com", user_agent: "ext-ua")
        internal_a = make_visit(country: "US", browser: "Firefox", device_type: "mobile",
                                referring_domain: "scorebase.org", user_agent: "int-ua-a")
        internal_b = make_visit(country: "FR", browser: "Safari", device_type: "tablet",
                                referring_domain: "scorebase.org", user_agent: "int-ua-b")

        Ahoy::Event.create!(visit: external,   name: "$view", properties: { "page" => "/scores" },     time: noon)
        Ahoy::Event.create!(visit: internal_a, name: "$view", properties: { "page" => "/scores/123" }, time: noon)
        Ahoy::Event.create!(visit: internal_b, name: "$view", properties: { "page" => "/scores/456" }, time: noon)
        Ahoy::Event.create!(visit: internal_b, name: "SMD click", properties: { "score_id" => 7 },    time: noon)

        described_class.aggregate_for!(date)
        ds = DailyStat.find_by!(date: date)

        # only the external visit counts
        expect(ds.visits).to eq(1)
        expect(ds.countries).to eq("DE" => 1)
        expect(ds.browsers).to eq("Chrome" => 1)
        expect(ds.devices).to eq("desktop" => 1)
        expect(ds.referrers).to eq("google.com" => 1)
        expect(ds.user_agents).to eq("ext-ua" => 1)

        # but content engagement and revenue events stay unfiltered
        expect(ds.paths).to eq("/scores" => 1, "/scores/123" => 1, "/scores/456" => 1)
        expect(ds.smd_clicks_by_score).to eq("7" => 1)

        # ...while converting_visits tracks the filtered denominator, so the
        # internal visit's click does not count.
        expect(ds.converting_visits).to eq(0)
      end
    end

    context 'date scoping' do
      it 'does not pull in events from adjacent days' do
        v_today = make_visit
        Ahoy::Event.create!(visit: v_today, name: "$view", properties: { "page" => "/" }, time: noon)

        v_yesterday = make_visit(started_at: noon - 1.day)
        Ahoy::Event.create!(visit: v_yesterday, name: "$view", properties: { "page" => "/old" }, time: noon - 1.day)

        described_class.aggregate_for!(date)
        ds = DailyStat.find_by!(date: date)
        expect(ds.visits).to eq(1)
        expect(ds.paths).to eq("/" => 1)
      end
    end
  end

  describe '#total_smd_clicks' do
    it 'sums values across the smd_clicks_by_score JSON' do
      ds = DailyStat.new(smd_clicks_by_score: { "1" => 5, "2" => 3 })
      expect(ds.total_smd_clicks).to eq(8)
    end

    it 'returns 0 for a nil column' do
      expect(DailyStat.new(smd_clicks_by_score: nil).total_smd_clicks).to eq(0)
    end
  end

  describe ".returning_rates_for" do
    let(:today) { Date.new(2026, 5, 15) }

    def make_visit(date:, visitor_hash:, visitor_hash_next: nil)
      Ahoy::Visit.create!(
        started_at:        date.in_time_zone.beginning_of_day + 12.hours,
        visit_token:       SecureRandom.uuid,
        visitor_token:     SecureRandom.uuid,
        visitor_hash:      visitor_hash,
        visitor_hash_next: visitor_hash_next
      )
    end

    it "returns all zeros when no visits exist on the date" do
      expect(DailyStat.returning_rates_for(today))
        .to eq("7d" => 0.0, "30d" => 0.0, "90d" => 0.0, "180d" => 0.0)
    end

    it "computes the share of today's distinct visitors that also appeared in the window" do
      make_visit(date: today, visitor_hash: "a")
      make_visit(date: today, visitor_hash: "a")
      make_visit(date: today, visitor_hash: "b")
      make_visit(date: today, visitor_hash: "c")
      make_visit(date: today - 5.days, visitor_hash: "a")

      rates = DailyStat.returning_rates_for(today)
      expect(rates["7d"]).to  be_within(0.001).of(1.0 / 3)
      expect(rates["30d"]).to be_within(0.001).of(1.0 / 3)
    end

    it "matches across the salt rotation boundary via visitor_hash_next" do
      jul5  = Date.new(2026, 7, 5)
      jun30 = Date.new(2026, 6, 30)
      h2 = "shared_h2_hash"
      h1 = "shared_h1_hash"

      make_visit(date: jul5,  visitor_hash: h2, visitor_hash_next: "future")
      make_visit(date: jun30, visitor_hash: h1, visitor_hash_next: h2)

      expect(DailyStat.returning_rates_for(jul5)["7d"]).to eq(1.0)
    end

    it "excludes visits with nil visitor_hash from numerator and denominator" do
      make_visit(date: today,           visitor_hash: nil)
      make_visit(date: today,           visitor_hash: "a")
      make_visit(date: today - 3.days,  visitor_hash: "a")

      expect(DailyStat.returning_rates_for(today)["7d"]).to eq(1.0)
    end
  end

  describe ".aggregate_for! with returning_rates" do
    it "writes returning_rates JSON alongside existing fields" do
      midday_today = Date.current.in_time_zone.beginning_of_day + 12.hours
      visit = Ahoy::Visit.create!(
        started_at:        midday_today,
        visit_token:       SecureRandom.uuid,
        visitor_token:     SecureRandom.uuid,
        visitor_hash:      "today_hash"
      )
      Ahoy::Event.create!(
        visit:      visit,
        name:       "$view",
        time:       midday_today,
        properties: { "page" => "/" }
      )

      DailyStat.aggregate_for!(Date.current)

      stat = DailyStat.find_by(date: Date.current)
      expect(stat).to be_present
      expect(stat.returning_rates).to be_a(Hash)
      expect(stat.returning_rates.keys).to contain_exactly("7d", "30d", "90d", "180d")
    end
  end

  describe '#smd_conversion_rate' do
    it 'expresses converting visits as a percentage of visits' do
      stat = DailyStat.new(date: Date.current, visits: 160, converting_visits: 30)

      expect(stat.smd_conversion_rate).to eq(18.8)
    end

    it 'returns nil rather than dividing by zero on a day with no visits' do
      stat = DailyStat.new(date: Date.current, visits: 0, converting_visits: 3)

      expect(stat.smd_conversion_rate).to be_nil
    end

    it 'returns nil for rows aggregated before converting_visits was backfilled' do
      stat = DailyStat.new(date: Date.current, visits: 100, converting_visits: nil,
                           smd_clicks_by_score: { "1" => 40 })

      expect(stat.smd_conversion_rate).to be_nil
    end

    it 'stays within 100% when internal-referrer visits generate most of the clicks' do
      date = Date.new(2026, 4, 15)
      noon = date.in_time_zone.change(hour: 12)
      visit = lambda do |referring_domain|
        Ahoy::Visit.create!(started_at: noon, visit_token: SecureRandom.uuid,
                            visitor_token: SecureRandom.uuid, referring_domain: referring_domain)
      end

      converting_external = visit.call("google.com")
      visit.call("bing.com")
      internal = visit.call("scorebase.org")

      Ahoy::Event.create!(visit: converting_external, name: "$view", properties: { "page" => "/" }, time: noon)
      Ahoy::Event.create!(visit: converting_external, name: "SMD click", properties: { "score_id" => 1 }, time: noon)
      5.times { Ahoy::Event.create!(visit: internal, name: "SMD click", properties: { "score_id" => 2 }, time: noon) }

      DailyStat.aggregate_for!(date)
      stat = DailyStat.find_by!(date: date)

      expect(stat.visits).to eq(2)
      expect(stat.total_smd_clicks).to eq(6)
      expect(stat.converting_visits).to eq(1)
      expect(stat.smd_conversion_rate).to eq(50.0)
    end
  end
end
