# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HubPages" do
  describe "GET /genres" do
    it "returns success" do
      get genres_path
      expect(response).to have_http_status(:success)
    end

    it "lists genres from the genre field" do
      12.times { create(:score, genre: "Motet", genre_status: "normalized") }

      get genres_path
      expect(response.body).to include("Motet")
    end
  end

  describe "GET /genres/:slug" do
    it "returns success for genre with enough scores" do
      12.times { create(:score, genre: "Motet", genre_status: "normalized") }

      get genre_path(slug: "motet")
      expect(response).to have_http_status(:success)
    end

    it "returns 404 for unknown genre" do
      get genre_path(slug: "nonexistent")
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when ?page=N is out of range" do
      12.times { create(:score, genre: "Motet", genre_status: "normalized") }

      get genre_path(slug: "motet", page: 99)
      expect(response).to have_http_status(:not_found)
    end

    it "noindexes page 2 but leaves page 1 indexable and self-canonical" do
      31.times { create(:score, genre: "Motet", genre_status: "normalized") }

      get genre_path(slug: "motet")
      expect(response.body).not_to include('name="robots"')
      expect(response.body).to include('<link rel="canonical" href="http://www.example.com/genres/motet">')

      get genre_path(slug: "motet", page: 2)
      expect(response.body).to include('content="noindex,follow"')
      expect(response.body).not_to include('rel="canonical"')
    end

    it "shows the instrument filter as selected when the param is not slug-cased" do
      12.times { create(:score, genre: "Motet", genre_status: "normalized", instruments: "Organ") }

      get genre_path(slug: "motet", instrument: "Organ")

      selected = Nokogiri::HTML(response.body).at_css("select#filter-instrument option[selected]")
      expect(selected["value"]).to eq("organ")
    end

    it "filters on the multi-word slugs the dropdown emits" do
      12.times { |i| create(:score, title: "Motet #{i}", genre: "Motet", genre_status: "normalized", instruments: "Double Bass") }
      12.times { |i| create(:score, title: "Piano piece #{i}", genre: "Motet", genre_status: "normalized", instruments: "Piano") }

      get genre_path(slug: "motet", instrument: "double-bass")

      expect(response.body).to include("Motet 0")
      expect(response.body).not_to include("Piano piece 0")
    end

    describe "pagination links" do
      def link_href(body, rel)
        Nokogiri::HTML(body).at_css(%(a[rel="#{rel}"]))&.[]("href")
      end

      it "links prev to the bare listing URL with no page param" do
        31.times { create(:score, genre: "Motet", genre_status: "normalized") }

        get genre_path(slug: "motet", page: 2)
        expect(link_href(response.body, "prev")).to eq("/genres/motet")
      end

      it "renders no next link when the last page is exactly full" do
        30.times { create(:score, genre: "Motet", genre_status: "normalized") }

        get genre_path(slug: "motet")
        expect(link_href(response.body, "next")).to be_nil
      end

      it "does not link to an attacker-supplied host" do
        31.times { create(:score, genre: "Motet", genre_status: "normalized") }

        get "/genres/motet?page=2&host=evil.example.com"
        expect(link_href(response.body, "prev")).not_to include("evil.example.com")
      end

      it "carries filter and sort params into the next link" do
        31.times { create(:score, genre: "Motet", genre_status: "normalized", instruments: "Piano") }

        get genre_path(slug: "motet", instrument: "piano", sort: "newest")
        expect(link_href(response.body, "next")).to eq("/genres/motet?instrument=piano&page=2&sort=newest")
      end
    end
  end

  describe "GET /composers" do
    it "returns success" do
      get composers_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /artists" do
    it "returns success" do
      get artists_path
      expect(response).to have_http_status(:success)
    end

    it "lists artists from SMD scores" do
      12.times { create(:score, :smd, artist: "Taylor Swift") }

      get artists_path
      expect(response.body).to include("Taylor Swift")
    end

    it "excludes Klassik-tagged SMD scores (no artist)" do
      12.times { create(:score, :smd_klassik) }

      get artists_path
      expect(response.body).not_to include("Johann Sebastian Bach")
    end
  end

  describe "GET /artists/:slug" do
    it "returns success for artist with enough scores" do
      12.times { create(:score, :smd, artist: "Taylor Swift") }

      get artist_path(slug: "taylor-swift")
      expect(response).to have_http_status(:success)
    end

    it "returns 404 for unknown artist" do
      get artist_path(slug: "nonexistent")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /instruments" do
    it "returns success" do
      get instruments_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /ensembles" do
    it "returns success with both grouped sections" do
      12.times { create(:score, :smd, smd_category: "Concert Band") }
      12.times { create(:score, :smd, smd_category: "SATB Choir") }

      get ensembles_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Bands &amp; Orchestras")
      expect(response.body).to include("Choirs")
      expect(response.body).to include("Concert Band")
      expect(response.body).to include("SATB Choir")
    end

    it "renders the German variant with translated ensemble names" do
      12.times { create(:score, :smd, smd_category: "Concert Band") }

      get ensembles_path(locale: :de)
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Blasorchester")
      expect(response.body).not_to include("Concert Band")
    end
  end

  describe "GET /ensembles/:slug" do
    it "returns success and lists reps of that category with buyer-query title" do
      12.times { create(:score, :smd, smd_category: "Concert Band", title: "Concert Band Rep") }

      get ensemble_path(slug: "concert-band")
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Concert Band Sheet Music")
      expect(response.body).to include("Concert Band Rep")
    end

    it "excludes hidden arrangement members and other categories" do
      12.times { create(:score, :smd, smd_category: "Concert Band") }
      create(:score, :smd, smd_category: "Concert Band", group_key: "g",
                           is_group_representative: false, title: "Hidden Member Part")
      create(:score, :smd, smd_category: "SATB Choir", title: "Some Choir Piece")

      get ensemble_path(slug: "concert-band")
      expect(response.body).not_to include("Hidden Member Part")
      expect(response.body).not_to include("Some Choir Piece")
      # The hero @total_count must be the deduped rep count (12), not 13 — a
      # regression dropping deduplicate_arrangements would show a part-inflated count.
      count = response.body[/color-accent\)\] font-bold">(\d[\d,]*)</, 1]
      expect(count).to eq("12")
    end

    it "filters by an SMD arranger resolved against the page's own scope" do
      # Regression: SMD arrangers aren't in the classical composer hub, so the old
      # composer_name_from_slug path resolved to nil -> where(composer: nil) -> empty page.
      8.times { create(:score, :smd, smd_category: "Concert Band", composer: "Michael Brown", title: "MB Chart") }
      4.times { create(:score, :smd, smd_category: "Concert Band", composer: "Jane Doe", title: "JD Chart") }

      get ensemble_path(slug: "concert-band", composer: "michael-brown")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("MB Chart")
      expect(response.body).not_to include("JD Chart")
    end

    it "renders the German variant with a translated heading" do
      12.times { create(:score, :smd, smd_category: "Concert Band") }

      get ensemble_path(slug: "concert-band", locale: :de)
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Blasorchester Noten")
    end

    it "returns 404 for a below-threshold category" do
      5.times { create(:score, :smd, smd_category: "Concert Band") }

      get ensemble_path(slug: "concert-band")
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for an unknown slug" do
      get ensemble_path(slug: "nonexistent")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /genres/:genre_slug/:instrument_slug" do
    def motet_with(instruments)
      instruments.each do |instrument|
        12.times { create(:score, genre: "Motet", genre_status: "normalized", instruments: instrument) }
      end
    end

    def instrument_row(body)
      Nokogiri::HTML(body).at_css(%(nav[aria-label="#{I18n.t('hub.common_instruments')}"]))
    end

    it "marks the current instrument and links to its siblings" do
      motet_with(%w[Organ Piano Violin Cello])

      get genre_instrument_path(genre_slug: "motet", instrument_slug: "organ")

      row = instrument_row(response.body)
      current = row.at_css('[aria-current="page"]')
      expect(current.name).to eq("span")
      expect(current.text).to include("Organ")
      expect(row.css("a").map { |a| a["href"] })
        .to contain_exactly("/genres/motet/piano", "/genres/motet/violin", "/genres/motet/cello")
    end

    it "keeps the row wherever the hub itself shows one" do
      motet_with(%w[Organ Piano Violin])

      get genre_instrument_path(genre_slug: "motet", instrument_slug: "organ")

      expect(instrument_row(response.body).css("a").map { |a| a["href"] })
        .to contain_exactly("/genres/motet/piano", "/genres/motet/violin")
    end

    it "hides the row when the current instrument leaves fewer than two links" do
      motet_with(%w[Organ Piano])

      get genre_instrument_path(genre_slug: "motet", instrument_slug: "organ")

      expect(instrument_row(response.body)).to be_nil
    end
  end
end
