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
end
