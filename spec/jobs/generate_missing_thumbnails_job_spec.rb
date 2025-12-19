# frozen_string_literal: true

require "rails_helper"

RSpec.describe GenerateMissingThumbnailsJob do
  it "enqueues jobs only for scores needing thumbnails" do
    needs_work = create(:score, thumbnail_url: "https://example.com/thumb.png")
    already_done = create(:score, thumbnail_url: "https://example.com/thumb2.png")
    already_done.thumbnail_image.attach(io: StringIO.new("x"), filename: "t.webp", content_type: "image/webp")

    expect { described_class.perform_now }.to have_enqueued_job(GenerateThumbnailJob).with(needs_work.id).exactly(1).times
  end

  it "respects source filter" do
    pdmx = create(:score, source: "pdmx", thumbnail_url: "https://example.com/1.png")
    cpdl = create(:score, source: "cpdl", thumbnail_url: "https://example.com/2.png")

    expect { described_class.perform_now(source: "cpdl") }.to have_enqueued_job(GenerateThumbnailJob).with(cpdl.id).exactly(1).times
  end

  it "respects limit" do
    create_list(:score, 3, thumbnail_url: "https://example.com/thumb.png")

    expect { described_class.perform_now(limit: 2) }.to have_enqueued_job(GenerateThumbnailJob).exactly(2).times
  end
end
