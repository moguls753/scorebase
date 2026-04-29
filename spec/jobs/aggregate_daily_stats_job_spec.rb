require 'rails_helper'

RSpec.describe AggregateDailyStatsJob, type: :job do
  def make_visit(at)
    Ahoy::Visit.create!(
      started_at: at,
      visit_token: SecureRandom.uuid,
      visitor_token: SecureRandom.uuid
    )
  end

  def add_pageview(visit, at)
    Ahoy::Event.create!(visit: visit, name: "$view", properties: { "page" => "/" }, time: at)
  end

  describe '#perform' do
    it 'aggregates today and yesterday into DailyStat rows' do
      today_visit     = make_visit(Time.current)
      yesterday_visit = make_visit(1.day.ago)
      add_pageview(today_visit,     Time.current)
      add_pageview(yesterday_visit, 1.day.ago)

      described_class.new.perform

      expect(DailyStat.find_by(date: Date.current)&.visits).to eq(1)
      expect(DailyStat.find_by(date: Date.current - 1)&.visits).to eq(1)
    end

    it 'prunes Ahoy data older than the retention window' do
      old_visit     = make_visit(35.days.ago)
      recent_visit  = make_visit(20.days.ago)
      add_pageview(old_visit,    35.days.ago)
      add_pageview(recent_visit, 20.days.ago)

      expect { described_class.new.perform }
        .to change { Ahoy::Visit.count }.from(2).to(1)
        .and change { Ahoy::Event.count }.from(2).to(1)

      expect(Ahoy::Visit.exists?(recent_visit.id)).to be true
      expect(Ahoy::Event.where(time: 20.days.ago.beginning_of_day..20.days.ago.end_of_day).count).to eq(1)
    end
  end
end
