class AddGenreStatusGenreLowerIndex < ActiveRecord::Migration[8.1]
  def change
    # Expression index for by_genre scope: where(genre_status: "normalized").where("LOWER(genre) = ?", ...)
    add_index :scores, "genre_status, LOWER(genre)", name: "index_scores_on_genre_status_and_lower_genre"
  end
end
