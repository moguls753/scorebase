# frozen_string_literal: true

require "rails_helper"

RSpec.describe BackfillSearchColumnsJob do
  def stale_score(**attrs)
    score = create(:score, **attrs)
    # Reproduce the drift: rewrite the derived columns behind the callback's back.
    score.update_columns(title_search_normalized: "old junk", composer_search_normalized: "old junk")
    score
  end

  it "recomputes both search columns from their source columns" do
    score = stale_score(title: "Greensleeves - Piano", composer: "Dvořák, Antonín")

    described_class.new.perform

    score.reload
    expect(score.title_search_normalized).to eq("Greensleeves - Piano")
    expect(score.composer_search_normalized).to eq("Dvorak, Antonin")
  end

  it "strips accents rather than reordering names" do
    score = stale_score(title: "Fauré Requiem", composer: "Bartók, Béla")

    described_class.new.perform

    score.reload
    expect(score.title_search_normalized).to eq("Faure Requiem")
    expect(score.composer_search_normalized).to eq("Bartok, Bela")
  end

  it "leaves the source columns untouched" do
    score = stale_score(title: "Dvořák Symphony", composer: "Dvořák, Antonín")

    described_class.new.perform

    score.reload
    expect(score.title).to eq("Dvořák Symphony")
    expect(score.composer).to eq("Dvořák, Antonín")
  end

  it "skips rows already in sync so a re-run is a no-op" do
    create(:score, title: "Clean", composer: "Bach, Johann")

    stats = described_class.new.perform

    expect(stats[:updated]).to eq(0)
  end

  it "reports what it examined and changed" do
    stale_score(title: "One", composer: "A")
    create(:score, title: "Two", composer: "B")

    stats = described_class.new.perform

    expect(stats[:examined]).to eq(2)
    expect(stats[:updated]).to eq(1)
  end

  it "handles a nil composer without blowing up" do
    score = stale_score(title: "Anonymous Work", composer: nil)

    described_class.new.perform

    expect(score.reload.composer_search_normalized).to eq("")
  end
end
