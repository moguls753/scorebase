# frozen_string_literal: true

require "rails_helper"

RSpec.describe HubCacheWarmJob, type: :job do
  describe "#perform" do
    it "delegates to HubDataBuilder.warm_all" do
      expect(HubDataBuilder).to receive(:warm_all)
      described_class.new.perform
    end

    it "re-raises errors for job failure tracking" do
      allow(HubDataBuilder).to receive(:warm_all).and_raise(StandardError, "test error")

      expect { described_class.new.perform }.to raise_error(StandardError, "test error")
    end
  end
end
