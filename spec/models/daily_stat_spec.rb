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
      end

      it 'aggregates into the dashboard JSON shape' do
        described_class.aggregate_for!(date)
        ds = DailyStat.find_by!(date: date)

        expect(ds.visits).to eq(3)
        expect(ds.paths).to eq("/scores/1" => 2, "/search" => 1)
        expect(ds.countries).to eq("DE" => 1, "US" => 1)
        expect(ds.browsers).to eq("Chrome" => 1, "Firefox" => 1)
        expect(ds.devices).to eq("desktop" => 1, "mobile" => 1)
        expect(ds.referrers).to eq("google.com" => 1, "direct" => 1)
        expect(ds.user_agents).to eq("UA-1" => 1, "UA-2" => 1)
        expect(ds.smd_clicks_by_score).to eq("42" => 2, "99" => 1)
      end

      it 'is idempotent on repeat invocation' do
        described_class.aggregate_for!(date)
        snapshot = DailyStat.find_by(date: date).attributes.except("updated_at")
        described_class.aggregate_for!(date)
        expect(DailyStat.find_by(date: date).attributes.except("updated_at")).to eq(snapshot)
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
end
