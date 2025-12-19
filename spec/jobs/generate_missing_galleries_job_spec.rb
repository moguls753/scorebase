# frozen_string_literal: true

require "rails_helper"

RSpec.describe GenerateMissingGalleriesJob do
  it "enqueues jobs only for scores needing galleries" do
    needs_work = create(:score, pdf_path: "test.pdf")
    already_done = create(:score, pdf_path: "test2.pdf")
    already_done.score_pages.create!(page_number: 1)

    expect { described_class.perform_now }.to have_enqueued_job(GenerateGalleryJob).with(needs_work.id).exactly(1).times
  end

  it "respects source filter" do
    pdmx = create(:score, source: "pdmx", pdf_path: "1.pdf")
    cpdl = create(:score, source: "cpdl", pdf_path: "2.pdf")

    expect { described_class.perform_now(source: "cpdl") }.to have_enqueued_job(GenerateGalleryJob).with(cpdl.id).exactly(1).times
  end

  it "respects limit" do
    create_list(:score, 3, pdf_path: "test.pdf")

    expect { described_class.perform_now(limit: 2) }.to have_enqueued_job(GenerateGalleryJob).exactly(2).times
  end
end
