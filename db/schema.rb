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

ActiveRecord::Schema[8.1].define(version: 2025_12_15_154524) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "composer_mappings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "normalized_name"
    t.string "original_name", null: false
    t.string "source"
    t.datetime "updated_at", null: false
    t.boolean "verified", default: false, null: false
    t.index ["normalized_name"], name: "index_composer_mappings_on_normalized_name"
    t.index ["original_name"], name: "index_composer_mappings_on_original_name", unique: true
  end

  create_table "daily_stats", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date"
    t.datetime "updated_at", null: false
    t.integer "visits", default: 0
    t.index ["date"], name: "index_daily_stats_on_date", unique: true
  end

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
    t.string "normalization_status", default: "pending", null: false
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
    t.index ["normalization_status"], name: "index_scores_on_normalization_status"
    t.index ["num_parts"], name: "index_scores_on_num_parts"
    t.index ["rating"], name: "index_scores_on_rating"
    t.index ["source"], name: "index_scores_on_source"
    t.index ["time_signature"], name: "index_scores_on_time_signature"
    t.index ["views"], name: "index_scores_on_views"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
end
