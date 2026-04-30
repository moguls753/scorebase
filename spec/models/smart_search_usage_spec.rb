require "rails_helper"

RSpec.describe SmartSearchUsage, type: :model do
  describe ".utc_today" do
    it "returns the current UTC date regardless of Time.zone" do
      Time.use_zone("America/Los_Angeles") do
        travel_to Time.utc(2026, 4, 27, 5, 0) do
          expect(described_class.utc_today).to eq(Date.new(2026, 4, 27))
        end
      end
    end
  end

  describe ".try_consume!" do
    let(:today) { described_class.utc_today }

    it "creates the day's row, returns the date, and increments count" do
      first_result = nil
      expect { first_result = described_class.try_consume!(cap: 20) }
        .to change { described_class.where(date: today).pick(:count) }.from(nil).to(1)
      expect(first_result).to eq(today)
      expect(described_class.try_consume!(cap: 20)).to eq(today)
    end

    it "returns nil and does not increment when at cap" do
      described_class.create!(date: today, count: 20)
      expect(described_class.try_consume!(cap: 20)).to be_nil
      expect(described_class.where(date: today).pick(:count)).to eq(20)
    end
  end

  describe ".refund!" do
    let(:today) { described_class.utc_today }

    it "decrements the row for the given date" do
      described_class.create!(date: today, count: 5)
      described_class.refund!(today)
      expect(described_class.where(date: today).pick(:count)).to eq(4)
    end

    it "does not go below zero" do
      described_class.create!(date: today, count: 0)
      described_class.refund!(today)
      expect(described_class.where(date: today).pick(:count)).to eq(0)
    end

    it "is a no-op when given nil" do
      described_class.create!(date: today, count: 3)
      expect { described_class.refund!(nil) }
        .not_to change { described_class.where(date: today).pick(:count) }
    end
  end

  describe "charge-before-midnight, refund-after-midnight" do
    it "refunds the originally charged date, not today" do
      yesterday_utc = Date.new(2026, 4, 27)
      today_utc     = Date.new(2026, 4, 28)
      charged_date  = nil

      travel_to(Time.utc(2026, 4, 27, 23, 59, 50)) do
        charged_date = SmartSearchUsage.try_consume!(cap: 20)
      end
      expect(charged_date).to eq(yesterday_utc)

      travel_to(Time.utc(2026, 4, 28, 0, 0, 10)) do
        SmartSearchUsage.refund!(charged_date)
      end

      expect(SmartSearchUsage.where(date: yesterday_utc).pick(:count)).to eq(0)
      expect(SmartSearchUsage.where(date: today_utc).count).to eq(0)
    end
  end
end
