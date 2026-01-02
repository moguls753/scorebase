# frozen_string_literal: true

require "rails_helper"

RSpec.describe NormalizePeriodsJob, type: :job do
  describe "#perform" do
    it "only processes composer_normalized scores" do
      pending_composer = create(:score, composer: "Bach, Johann Sebastian", composer_status: :pending)
      normalized_composer = create(:score, composer: "Bach, Johann Sebastian", composer_status: :normalized)

      described_class.perform_now(limit: 100)

      expect(normalized_composer.reload.period_status).to eq("normalized")
      expect(pending_composer.reload.period_status).to eq("pending")
    end

    it "sets period from PeriodInferrer lookup" do
      score = create(:score, composer: "Bach, Johann Sebastian", composer_status: :normalized)

      described_class.perform_now(limit: 100)

      expect(score.reload.period).to eq("Baroque")
      expect(score.period_status).to eq("normalized")
    end

    it "leaves as pending when composer not in lookup (for next stage)" do
      score = create(:score, composer: "Unknown, Joe", composer_status: :normalized)

      described_class.perform_now(limit: 100)

      expect(score.reload.period).to be_nil
      expect(score.period_status).to eq("pending")
    end

    it "skips already processed scores" do
      score = create(:score, composer: "Bach, Johann Sebastian", composer_status: :normalized, period_status: :normalized)

      expect {
        described_class.perform_now(limit: 100)
      }.not_to change { score.reload.updated_at }
    end
  end
end
