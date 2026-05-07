require "rails_helper"

RSpec.describe SmartSearchQuota do
  let(:ip_hash) { Digest::SHA256.hexdigest("test|1.1.1.1") }

  describe ".try_consume!" do
    it "returns the charged date and increments the site counter on the happy path" do
      result = nil
      expect { result = described_class.try_consume!(ip_hash: ip_hash) }
        .to change { SmartSearchUsage.where(date: SmartSearchUsage.utc_today).pick(:count) }.from(nil).to(1)
      expect(result).to eq(SmartSearchUsage.utc_today)
    end

    it "returns :per_ip_limit when the IP has reached PER_IP_DAILY_LIMIT" do
      SmartSearchQuota::PER_IP_DAILY_LIMIT.times do |i|
        create(:smart_search_query, query: "q#{i}", ip_hash: ip_hash, created_at: 1.hour.ago)
      end

      expect(described_class.try_consume!(ip_hash: ip_hash)).to eq(:per_ip_limit)
      expect(SmartSearchUsage.where(date: SmartSearchUsage.utc_today).count).to eq(0)
    end

    it "returns :site_limit when the site is capped, even if the IP is below its limit" do
      SmartSearchUsage.create!(date: SmartSearchUsage.utc_today, count: SmartSearchUsage::DEFAULT_CAP)

      expect(described_class.try_consume!(ip_hash: ip_hash)).to eq(:site_limit)
    end

    it "ignores errored prior queries when counting per-IP usage" do
      SmartSearchQuota::PER_IP_DAILY_LIMIT.times do |i|
        create(:smart_search_query, query: "q#{i}", ip_hash: ip_hash, error: "RAG down", created_at: 1.hour.ago)
      end

      expect(described_class.try_consume!(ip_hash: ip_hash)).to eq(SmartSearchUsage.utc_today)
    end
  end

  describe ".refund!" do
    let(:today) { SmartSearchUsage.utc_today }

    it "decrements the site counter for the charged date" do
      SmartSearchUsage.create!(date: today, count: 5)

      expect { described_class.refund!(today) }
        .to change { SmartSearchUsage.where(date: today).pick(:count) }.from(5).to(4)
    end

    it "is a no-op when given nil" do
      SmartSearchUsage.create!(date: today, count: 3)

      expect { described_class.refund!(nil) }
        .not_to change { SmartSearchUsage.where(date: today).pick(:count) }
    end
  end
end
