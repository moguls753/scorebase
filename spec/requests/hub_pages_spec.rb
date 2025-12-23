# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HubPages" do
  describe "GET /genres" do
    it "returns success" do
      get genres_path
      expect(response).to have_http_status(:success)
    end

    it "lists genres from the genre field" do
      12.times { create(:score, genre: "Sacred") }

      get genres_path
      expect(response.body).to include("Sacred")
    end
  end

  describe "GET /genres/:slug" do
    it "returns success for genre with enough scores" do
      12.times { create(:score, genre: "Motet") }

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

  describe "GET /instruments" do
    it "returns success" do
      get instruments_path
      expect(response).to have_http_status(:success)
    end
  end
end
