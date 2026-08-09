require 'rails_helper'

RSpec.describe DailyStat, type: :model do
  describe '.aggregate_for!' do
    let(:date) { DailyStat::REFERRER_CAPTURE_STARTED_ON + 4 }
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
      end

      it 'aggregates the human-visit basis into the dashboard JSON shape' do
        described_class.aggregate_for!(date)
        ds = DailyStat.find_by!(date: date)

        expect(ds.visits).to eq(2)
        expect(ds.human_visits).to eq(1)
        expect(ds.countries).to eq("DE" => 1)
        expect(ds.devices).to eq("desktop" => 1)
        expect(ds.referrers).to eq("google.com" => 1)
        expect(ds.paths).to eq("/scores/1" => 1)
        expect(ds.smd_clicks_by_score).to eq("42" => 2)
        expect(ds.human_converting_visits).to eq(1)
      end

      it 'is idempotent on repeat invocation' do
        described_class.aggregate_for!(date)
        snapshot = DailyStat.find_by(date: date).attributes.except("updated_at")
        described_class.aggregate_for!(date)
        expect(DailyStat.find_by(date: date).attributes.except("updated_at")).to eq(snapshot)
      end
    end

    context 'internal-referrer filtering' do
      it 'counts only external human visits across every breakdown' do
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

        expect(ds.visits).to eq(1)
        expect(ds.human_visits).to eq(1)
        expect(ds.countries).to eq("DE" => 1)
        expect(ds.devices).to eq("desktop" => 1)
        expect(ds.referrers).to eq("google.com" => 1)
        expect(ds.paths).to eq("/scores" => 1)
        expect(ds.smd_clicks_by_score).to eq({})
        expect(ds.human_converting_visits).to eq(0)
      end
    end

    context 'before referrer capture began' do
      let(:earlier) { DailyStat::REFERRER_CAPTURE_STARTED_ON - 1 }
      let(:earlier_noon) { earlier.in_time_zone.change(hour: 12) }

      it 'leaves the human columns nil rather than writing a degraded value' do
        visit = make_visit(started_at: earlier_noon)
        2.times { Ahoy::Event.create!(visit: visit, name: "$view", properties: { "page" => "/" }, time: earlier_noon) }

        described_class.aggregate_for!(earlier)
        ds = DailyStat.find_by!(date: earlier)

        expect(ds.visits).to eq(1)
        expect(ds.human_visits).to be_nil
        expect(ds.human_converting_visits).to be_nil
      end
    end

    context 'date scoping' do
      it 'does not pull in events from adjacent days' do
        v_today = make_visit(referring_domain: "google.com")
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

  describe '.in_window' do
    it 'spans exactly n calendar days ending today' do
      create(:daily_stat, date: Date.current - 7)
      edge = create(:daily_stat, date: Date.current - 6)

      expect(DailyStat.in_window(7)).to contain_exactly(edge)
    end
  end

  describe '.summary' do
    it 'rolls measured rows up and ignores unmeasured rows on both sides of every ratio' do
      create(:daily_stat, date: Date.current, visits: 400, human_visits: 200,
                          human_converting_visits: 6, smd_clicks_by_score: { "1" => 8 })
      create(:daily_stat, date: Date.current - 1, visits: 900, human_visits: nil,
                          human_converting_visits: nil, smd_clicks_by_score: { "1" => 500 })

      expect(DailyStat.in_window(7).summary).to eq(
        days: 1, visits: 400, human_visits: 200, avg_visits: 400, avg_human: 200,
        human_share: 50.0, smd_clicks: 8, converting: 6, conversion_rate: 3.0
      )
    end

    it 'returns nil rates rather than dividing by zero on a window with no measured rows' do
      create(:daily_stat, date: Date.current, visits: 400, human_visits: nil)

      summary = DailyStat.in_window(7).summary
      expect(summary[:human_share]).to be_nil
      expect(summary[:conversion_rate]).to be_nil
    end
  end
end
