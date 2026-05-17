require "rails_helper"

RSpec.describe VisitorHash do
  describe ".from" do
    it "returns nil when ip is blank" do
      expect(VisitorHash.from(ip: nil, user_agent: "ua")).to be_nil
      expect(VisitorHash.from(ip: "",  user_agent: "ua")).to be_nil
    end

    it "returns a 64-character hex digest for a valid (ip, ua)" do
      hash = VisitorHash.from(ip: "1.2.3.4", user_agent: "Mozilla/5.0")
      expect(hash).to match(/\A[0-9a-f]{64}\z/)
    end

    it "is deterministic for the same (ip, ua, date)" do
      d = Date.new(2026, 3, 1)
      h1 = VisitorHash.from(ip: "1.2.3.4", user_agent: "ua", date: d)
      h2 = VisitorHash.from(ip: "1.2.3.4", user_agent: "ua", date: d)
      expect(h1).to eq(h2)
    end

    it "produces different hashes across calendar half-year boundaries" do
      h1 = VisitorHash.from(ip: "1.2.3.4", user_agent: "ua", date: Date.new(2026, 3, 1))
      h2 = VisitorHash.from(ip: "1.2.3.4", user_agent: "ua", date: Date.new(2026, 9, 1))
      expect(h1).not_to eq(h2)
    end
  end

  describe ".from_next" do
    it "matches what .from would return on the next period's first day" do
      jun30 = Date.new(2026, 6, 30)
      jul1  = Date.new(2026, 7, 1)
      next_hash   = VisitorHash.from_next(ip: "1.2.3.4", user_agent: "ua", date: jun30)
      future_hash = VisitorHash.from(ip: "1.2.3.4", user_agent: "ua", date: jul1)
      expect(next_hash).to eq(future_hash)
    end

    it "matches across the December to January year boundary" do
      dec31 = Date.new(2026, 12, 31)
      jan1  = Date.new(2027, 1, 1)
      next_hash   = VisitorHash.from_next(ip: "1.2.3.4", user_agent: "ua", date: dec31)
      future_hash = VisitorHash.from(ip: "1.2.3.4", user_agent: "ua", date: jan1)
      expect(next_hash).to eq(future_hash)
    end
  end
end
