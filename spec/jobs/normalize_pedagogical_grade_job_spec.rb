# frozen_string_literal: true

require "rails_helper"

RSpec.describe NormalizePedagogicalGradeJob, type: :job do
  let(:job) { described_class.new }

  describe "#eligible_scores" do
    it "excludes SMD scores (SMD grade comes from SmdStatusNormalizer)" do
      smd  = create(:score, :smd,   composer_status: :normalized, grade_status: :pending)
      free = create(:score, :imslp, composer_status: :normalized, grade_status: :pending, external_id: nil)

      scope = job.send(:eligible_scores, 100)

      expect(scope).to include(free)
      expect(scope).not_to include(smd)
    end

    it "requires composer_status: normalized" do
      pending    = create(:score, :imslp, composer_status: :pending,    grade_status: :pending, external_id: nil)
      normalized = create(:score, :imslp, composer_status: :normalized, grade_status: :pending, external_id: nil)

      scope = job.send(:eligible_scores, 100)

      expect(scope).to     include(normalized)
      expect(scope).not_to include(pending)
    end
  end

  describe "#propagate_upstream_failures" do
    it "marks non-SMD composer-failed scores as grade not_applicable" do
      score = create(:score, :imslp, composer_status: :failed, grade_status: :pending, external_id: nil)

      job.send(:propagate_upstream_failures)

      expect(score.reload.grade_status).to eq("not_applicable")
      expect(score.grade_source).to eq("no_composer")
    end

    it "does not touch SMD composer-failed scores" do
      score = create(:score, :smd, composer_status: :failed, grade_status: :pending)

      job.send(:propagate_upstream_failures)

      expect(score.reload.grade_status).to eq("pending")
      expect(score.grade_source).to be_nil
    end
  end
end
