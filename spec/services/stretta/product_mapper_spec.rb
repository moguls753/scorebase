# frozen_string_literal: true

require "rails_helper"

RSpec.describe Stretta::ProductMapper do
  def product(**overrides)
    { handle: "148059", title: "Großer Gott, wir loben dich", subtitle: "F-Dur",
      vendor: "Carus Verlag", itemtype: "Partitur", instrument: "2 Trompeten (C), Orgel",
      slug_de: "leitner-grosser-gott-nr-148059", price: 5.5, available_for_sale: true,
      authors: [{ role: "author", name: "Hans Leitner", slug: "hans-leitner" }] }.merge(overrides)
  end

  subject(:mapper) { described_class.new }

  # A bulk write runs no callbacks, so the column the FTS triggers index has to be
  # set here. Missed, the catalogue is unfindable behind a healthy-looking database.
  it "sets the normalised search columns the FTS triggers actually index" do
    attributes = mapper.call(product)

    expect(attributes[:title_search_normalized]).to eq("Grosser Gott, wir loben dich")
    expect(attributes[:composer_search_normalized]).to be_present
  end

  it "drops a product without a title" do
    expect(mapper.call(product(title: nil))).to be_nil
  end

  # upsert_all rejects a batch whose rows differ in shape, mid-import.
  it "returns the same keys whatever the input" do
    rich = mapper.call(product(difficulty: "3"))
    sparse = mapper.call(product(difficulty: nil, authors: [], instrument: nil))

    expect(sparse.keys).to match_array(rich.keys)
  end

  describe "composer" do
    it "writes the canonical name on a mapping hit" do
      ComposerMapping.create!(original_name: "Hans Leitner", normalized_name: "Leitner, Hans", source: "test")

      expect(mapper.call(product)).to include(composer: "Leitner, Hans", composer_status: "normalized")
    end

    it "leaves the raw name pending on a miss" do
      expect(mapper.call(product)).to include(composer: "Hans Leitner", composer_status: "pending")
    end

    # authors[0] is the arranger on an arrangement; only role == author is the composer.
    it "ignores an arranger" do
      attributes = mapper.call(product(authors: [{ role: "arranger", name: "Someone" }]))

      expect(attributes).to include(composer: nil, composer_status: "not_applicable")
    end

    it "does not queue Traditional for the LLM" do
      attributes = mapper.call(product(authors: [{ role: "author", name: "Traditional" }]))

      expect(attributes[:composer_status]).to eq("not_applicable")
    end
  end

  describe "difficulty" do
    it "maps a level to its grade and German label" do
      expect(mapper.call(product(difficulty: "3")))
        .to include(pedagogical_grade: "Grade 3-4", pedagogical_grade_de: "mittelschwer",
                    grade_source: "stretta", grade_status: "normalized")
    end

    # 48,939 rows carry a range; to_i takes the lower bound where Integer() raises.
    it "takes the lower bound of a two-step range" do
      expect(mapper.call(product(difficulty: "2-3"))[:pedagogical_grade]).to eq("Grade 2-3")
    end

    it "refuses a range wider than two steps rather than guessing" do
      expect(mapper.call(product(difficulty: "1-5"))).to include(grade_status: "not_applicable",
                                                                pedagogical_grade: nil)
    end
  end

  # These three would otherwise walk into jobs that are not filtered by source.
  it "keeps the row out of the RAG, genre and period pipelines" do
    expect(mapper.call(product)).to include(rag_status: "not_applicable", genre_status: "not_applicable",
                                            period_status: "not_applicable")
  end

  it "keeps the raw title in the metadata so the work key never carries the display title" do
    attributes = mapper.call(product)

    expect(attributes[:stretta_metadata]).to include(raw_title: "Großer Gott, wir loben dich", subtitle: "F-Dur")
    expect(attributes[:work_key]).to eq("grosser gott wir loben dich|leitner")
  end
end
