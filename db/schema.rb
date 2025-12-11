# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2025_12_10_233957) do
  create_table "scores", force: :cascade do |t|
    t.integer "complexity"
    t.string "composer"
    t.string "cpdl_number"
    t.datetime "created_at", null: false
    t.string "data_path"
    t.text "description"
    t.string "editor"
    t.string "external_id"
    t.string "external_url"
    t.integer "favorites", default: 0
    t.text "genres"
    t.string "instruments"
    t.string "key_signature"
    t.string "language"
    t.string "license"
    t.text "lyrics"
    t.string "metadata_path"
    t.string "mid_path"
    t.string "mxl_path"
    t.integer "num_parts"
    t.integer "page_count"
    t.string "pdf_path"
    t.date "posted_date"
    t.decimal "rating", precision: 3, scale: 2
    t.string "source", default: "pdmx"
    t.text "tags"
    t.string "thumbnail_url"
    t.string "time_signature"
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "views", default: 0
    t.string "voicing"
    t.index ["complexity"], name: "index_scores_on_complexity"
    t.index ["composer"], name: "index_scores_on_composer"
    t.index ["external_id"], name: "index_scores_on_external_id"
    t.index ["key_signature"], name: "index_scores_on_key_signature"
    t.index ["num_parts"], name: "index_scores_on_num_parts"
    t.index ["rating"], name: "index_scores_on_rating"
    t.index ["source"], name: "index_scores_on_source"
    t.index ["time_signature"], name: "index_scores_on_time_signature"
    t.index ["views"], name: "index_scores_on_views"
  end
end
