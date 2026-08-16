# frozen_string_literal: true

require "rails_helper"

RSpec.describe Stretta::Classifier do
  def classify(**overrides)
    described_class.classify({ available_for_sale: true, title: "Missa brevis",
                               itemtype: "Partitur", instrument: "gemischter Chor (SATB)" }.merge(overrides))
  end

  it "accepts an allowlisted itemtype" do
    expect(classify).to have_attributes(accepted?: true, reason: :allowlist)
  end

  it "rejects a denylisted itemtype" do
    expect(classify(itemtype: "CD")).to have_attributes(accepted?: false, reason: :denylist)
  end

  it "rejects an itemtype on neither list rather than guessing" do
    expect(classify(itemtype: "Regenschirm")).to have_attributes(accepted?: false, reason: :unlisted_itemtype)
  end

  # 43,808 of 59,720 bare-"Buch" rows carry a scoring; "Buch (Gebunden)" never does.
  it "accepts a bare Buch that carries a scoring" do
    expect(classify(itemtype: "Buch")).to have_attributes(accepted?: true, reason: :book_with_scoring)
  end

  it "rejects a Buch without one" do
    expect(classify(itemtype: "Buch", instrument: nil)).to have_attributes(accepted?: false,
                                                                            reason: :book_without_scoring)
  end

  # The book rule's known cost: books *about* music that carry a category.
  it "rejects a Buch whose scoring is a subject, not an instrument" do
    expect(classify(itemtype: "Buch", instrument: "Theory")).to have_attributes(reason: :non_scoring_subject)
    expect(classify(itemtype: "Buch", instrument: "Libretto")).to have_attributes(reason: :non_scoring_subject)
  end

  describe "empty itemtype" do
    it "needs a scoring plus a page count or a preview PDF" do
      expect(classify(itemtype: "", pages: ["12"])).to have_attributes(accepted?: true)
      expect(classify(itemtype: "", preview_pdf: true)).to have_attributes(accepted?: true)
    end

    it "reads the shape the API client actually produces" do
      product = Stretta::Product.from_graphql(
        "handle" => "1", "availableForSale" => true,
        "texts" => { "value" => { title: "Werk", instrument: "Orgel", itemtype: "" }.to_json },
        "pages" => { "value" => '["20"]' }
      )

      expect(described_class.classify(product)).to have_attributes(accepted?: true,
                                                                  reason: :empty_itemtype_corroborated)
    end

    it "rejects an uncorroborated one" do
      expect(classify(itemtype: nil)).to have_attributes(accepted?: false, reason: :empty_itemtype_uncorroborated)
    end
  end

  # 7.4% of the catalogue; both URL forms 404, so these are dead links, not products.
  it "rejects anything not for sale before looking at anything else" do
    expect(classify(available_for_sale: false)).to have_attributes(accepted?: false, reason: :not_for_sale)
  end

  it "rejects a row without a title, which could not become a Score anyway" do
    expect(classify(title: " ")).to have_attributes(accepted?: false, reason: :no_title)
  end
end
