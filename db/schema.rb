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

ActiveRecord::Schema[8.1].define(version: 2026_01_15_212931) do
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

  create_table "score_page_deletion_logs", force: :cascade do |t|
    t.text "context"
    t.datetime "deleted_at", null: false
    t.integer "page_number", null: false
    t.integer "score_id", null: false
    t.integer "score_page_id", null: false
    t.string "source"
    t.index ["deleted_at"], name: "index_score_page_deletion_logs_on_deleted_at"
    t.index ["score_id"], name: "index_score_page_deletion_logs_on_score_id"
  end

  create_table "score_pages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "page_number", null: false
    t.integer "score_id", null: false
    t.datetime "updated_at", null: false
    t.index ["score_id", "page_number"], name: "index_score_pages_on_score_id_and_page_number", unique: true
  end

  create_table "scores", force: :cascade do |t|
    t.integer "accidental_count"
    t.integer "ambitus_semitones"
    t.integer "arpeggio_mark_count"
    t.float "avg_chord_span"
    t.integer "beat_count"
    t.text "cadence_types"
    t.integer "chord_count"
    t.integer "chromatic_note_count"
    t.float "chromatic_ratio"
    t.text "clefs_used"
    t.integer "complexity"
    t.string "composer"
    t.string "composer_normalized"
    t.string "composer_status", default: "pending", null: false
    t.integer "computed_difficulty"
    t.float "contrary_motion_ratio"
    t.string "cpdl_number"
    t.datetime "created_at", null: false
    t.string "data_path"
    t.text "description"
    t.text "detected_instruments"
    t.float "duration_seconds"
    t.string "dynamic_range"
    t.string "editor"
    t.float "estimated_duration_seconds"
    t.integer "estimated_tempo_bpm"
    t.integer "event_count"
    t.text "expression_markings"
    t.string "external_id"
    t.string "external_url"
    t.datetime "extracted_at"
    t.text "extracted_lyrics"
    t.text "extraction_error"
    t.string "extraction_status", default: "pending", null: false
    t.integer "favorites", default: 0
    t.string "final_cadence"
    t.string "form_analysis"
    t.text "genre"
    t.string "genre_status", default: "pending", null: false
    t.integer "grace_note_count"
    t.string "grade_source"
    t.string "grade_status", default: "pending", null: false
    t.float "harmonic_rhythm"
    t.boolean "has_accompaniment"
    t.boolean "has_articulations"
    t.boolean "has_dynamics"
    t.boolean "has_extracted_lyrics"
    t.boolean "has_fermatas"
    t.boolean "has_ornaments"
    t.boolean "has_ottava"
    t.boolean "has_pedal_marks"
    t.boolean "has_tempo_changes"
    t.boolean "has_vocal"
    t.string "has_vocal_status", default: "pending", null: false
    t.string "highest_pitch"
    t.integer "index_version"
    t.datetime "indexed_at"
    t.text "instrument_families"
    t.string "instruments"
    t.string "instruments_status", default: "pending", null: false
    t.integer "interval_count"
    t.json "interval_distribution"
    t.boolean "is_instrumental"
    t.boolean "is_multi_movement"
    t.float "key_confidence"
    t.json "key_correlations"
    t.string "key_signature"
    t.string "language"
    t.integer "largest_interval"
    t.integer "leap_count"
    t.float "leaps_per_measure"
    t.string "license"
    t.string "lowest_pitch"
    t.text "lyrics"
    t.string "lyrics_language"
    t.integer "max_chord_span"
    t.integer "measure_count"
    t.float "melodic_complexity"
    t.string "melodic_contour"
    t.string "metadata_path"
    t.string "meter_classification"
    t.string "mid_path"
    t.integer "modulation_count"
    t.json "modulation_targets"
    t.text "modulations"
    t.integer "mordent_count"
    t.string "music21_version"
    t.string "musicxml_source"
    t.string "mxl_path"
    t.float "note_density"
    t.integer "num_parts"
    t.float "oblique_motion_ratio"
    t.integer "off_beat_count"
    t.integer "page_count"
    t.float "parallel_motion_ratio"
    t.text "part_names"
    t.string "pdf_path"
    t.string "pedagogical_grade"
    t.string "pedagogical_grade_de"
    t.string "period"
    t.string "period_status", default: "pending", null: false
    t.json "pitch_class_distribution"
    t.integer "pitch_count"
    t.json "pitch_range_per_part"
    t.date "posted_date"
    t.string "predominant_rhythm"
    t.string "rag_status", default: "pending", null: false
    t.decimal "rating", precision: 3, scale: 2
    t.integer "repeats_count"
    t.json "rhythm_distribution"
    t.float "rhythmic_variety"
    t.text "search_text"
    t.datetime "search_text_generated_at"
    t.integer "sections_count"
    t.float "simultaneous_note_avg"
    t.integer "slur_count"
    t.string "source", default: "pdmx"
    t.integer "stepwise_count"
    t.float "stepwise_motion_ratio"
    t.integer "syllable_count"
    t.float "syncopation_level"
    t.text "tags"
    t.integer "tempo_bpm"
    t.string "tempo_marking"
    t.float "tempo_referent"
    t.json "tessitura"
    t.string "texture_type"
    t.float "texture_variation"
    t.string "thumbnail_url"
    t.string "time_signature"
    t.string "title"
    t.string "title_normalized"
    t.float "total_quarter_length"
    t.integer "tremolo_count"
    t.integer "trill_count"
    t.integer "turn_count"
    t.integer "unique_chord_count"
    t.integer "unique_duration_count"
    t.integer "unique_pitches"
    t.datetime "updated_at", null: false
    t.float "vertical_density"
    t.integer "views", default: 0
    t.float "voice_independence"
    t.json "voice_ranges"
    t.string "voicing"
    t.string "voicing_status", default: "pending", null: false
    t.index "genre_status, LOWER(genre)", name: "index_scores_on_genre_status_and_lower_genre"
    t.index ["ambitus_semitones"], name: "index_scores_on_ambitus_semitones"
    t.index ["chromatic_ratio"], name: "index_scores_on_chromatic_ratio"
    t.index ["complexity"], name: "index_scores_on_complexity"
    t.index ["composer"], name: "index_scores_on_composer"
    t.index ["composer_normalized"], name: "index_scores_on_composer_normalized"
    t.index ["composer_status"], name: "index_scores_on_composer_status"
    t.index ["computed_difficulty"], name: "index_scores_on_computed_difficulty"
    t.index ["created_at"], name: "index_scores_on_created_at"
    t.index ["duration_seconds"], name: "index_scores_on_duration_seconds"
    t.index ["event_count"], name: "index_scores_on_event_count"
    t.index ["external_id"], name: "index_scores_on_external_id"
    t.index ["extraction_status"], name: "index_scores_on_extraction_status"
    t.index ["genre"], name: "index_scores_on_genre"
    t.index ["genre_status"], name: "index_scores_on_genre_status"
    t.index ["grade_status"], name: "index_scores_on_grade_status"
    t.index ["has_extracted_lyrics"], name: "index_scores_on_has_extracted_lyrics"
    t.index ["has_vocal"], name: "index_scores_on_has_vocal"
    t.index ["has_vocal_status"], name: "index_scores_on_has_vocal_status"
    t.index ["highest_pitch"], name: "index_scores_on_highest_pitch"
    t.index ["indexed_at"], name: "index_scores_on_indexed_at"
    t.index ["instruments"], name: "index_scores_on_instruments"
    t.index ["instruments_status"], name: "index_scores_on_instruments_status"
    t.index ["key_confidence"], name: "index_scores_on_key_confidence"
    t.index ["key_signature"], name: "index_scores_on_key_signature"
    t.index ["lowest_pitch"], name: "index_scores_on_lowest_pitch"
    t.index ["measure_count"], name: "index_scores_on_measure_count"
    t.index ["melodic_complexity"], name: "index_scores_on_melodic_complexity"
    t.index ["modulation_count"], name: "index_scores_on_modulation_count"
    t.index ["num_parts"], name: "index_scores_on_num_parts"
    t.index ["pedagogical_grade"], name: "index_scores_on_pedagogical_grade"
    t.index ["period"], name: "index_scores_on_period"
    t.index ["period_status"], name: "index_scores_on_period_status"
    t.index ["rag_status"], name: "index_scores_on_rag_status"
    t.index ["rating"], name: "index_scores_on_rating"
    t.index ["source"], name: "index_scores_on_source"
    t.index ["tempo_bpm"], name: "index_scores_on_tempo_bpm"
    t.index ["texture_type"], name: "index_scores_on_texture_type"
    t.index ["time_signature"], name: "index_scores_on_time_signature"
    t.index ["title_normalized"], name: "index_scores_on_title_normalized"
    t.index ["views"], name: "index_scores_on_views"
    t.index ["voicing"], name: "index_scores_on_voicing"
    t.index ["voicing_status"], name: "index_scores_on_voicing_status"
  end

  create_table "waitlist_signups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "locale", default: "en", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_waitlist_signups_on_email", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "score_pages", "scores", on_delete: :cascade
end
