require "rails_helper"

RSpec.describe HashedIp do
  describe ".from" do
    it "returns a 64-char hex digest" do
      expect(described_class.from("203.0.113.42")).to match(/\A[0-9a-f]{64}\z/)
    end

    it "is deterministic for the same IP" do
      expect(described_class.from("203.0.113.42")).to eq(described_class.from("203.0.113.42"))
    end

    it "differs across IPs" do
      expect(described_class.from("1.1.1.1")).not_to eq(described_class.from("2.2.2.2"))
    end
  end
end
