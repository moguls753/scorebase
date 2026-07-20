CREATE TABLE IF NOT EXISTS "schema_migrations" ("version" varchar NOT NULL PRIMARY KEY);
CREATE TABLE IF NOT EXISTS "ar_internal_metadata" ("key" varchar NOT NULL PRIMARY KEY, "value" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE IF NOT EXISTS "active_storage_blobs" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "key" varchar NOT NULL, "filename" varchar NOT NULL, "content_type" varchar, "metadata" text, "service_name" varchar NOT NULL, "byte_size" bigint NOT NULL, "checksum" varchar, "created_at" datetime(6) NOT NULL);
CREATE TABLE IF NOT EXISTS "active_storage_attachments" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar NOT NULL, "record_type" varchar NOT NULL, "record_id" bigint NOT NULL, "blob_id" bigint NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_c3b3935057"
FOREIGN KEY ("blob_id")
  REFERENCES "active_storage_blobs" ("id")
);
CREATE TABLE IF NOT EXISTS "active_storage_variant_records" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "blob_id" bigint NOT NULL, "variation_digest" varchar NOT NULL, CONSTRAINT "fk_rails_993965df05"
FOREIGN KEY ("blob_id")
  REFERENCES "active_storage_blobs" ("id")
);
CREATE TABLE IF NOT EXISTS "composer_mappings" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "original_name" varchar NOT NULL, "normalized_name" varchar, "source" varchar, "verified" boolean DEFAULT FALSE NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE IF NOT EXISTS "score_pages" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "score_id" integer NOT NULL, "page_number" integer NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_6636f54ed1"
FOREIGN KEY ("score_id")
  REFERENCES "scores" ("id")
 ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS "waitlist_signups" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "email" varchar NOT NULL, "locale" varchar DEFAULT 'en' NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE IF NOT EXISTS "score_page_deletion_logs" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "score_page_id" integer NOT NULL, "score_id" integer NOT NULL, "page_number" integer NOT NULL, "deleted_at" datetime(6) NOT NULL, "source" varchar, "context" text);
CREATE TABLE IF NOT EXISTS "daily_stats" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "date" date, "visits" integer DEFAULT 0, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "smd_clicks_by_score" json DEFAULT '{}', "user_agents" json, "countries" json, "referrers" json, "paths" json, "devices" json, "browsers" json, "returning_rates" json, "cross_link_visits_by_score" json DEFAULT '{}', "converting_visits" integer);
CREATE TABLE IF NOT EXISTS "score_smd_matches" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "score_id" integer NOT NULL, "smd_score_id" integer NOT NULL, "rank" integer NOT NULL, "suppressed" boolean DEFAULT FALSE NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_ef221d632c"
FOREIGN KEY ("score_id")
  REFERENCES "scores" ("id")
 ON DELETE CASCADE, CONSTRAINT "fk_rails_b48d809b00"
FOREIGN KEY ("smd_score_id")
  REFERENCES "scores" ("id")
 ON DELETE CASCADE);
CREATE INDEX "index_score_smd_matches_on_score_id" ON "score_smd_matches" ("score_id");
CREATE INDEX "index_score_smd_matches_on_smd_score_id" ON "score_smd_matches" ("smd_score_id");
CREATE UNIQUE INDEX "index_score_smd_matches_on_score_id_and_smd_score_id" ON "score_smd_matches" ("score_id", "smd_score_id");
CREATE UNIQUE INDEX "index_score_smd_matches_on_score_id_and_rank" ON "score_smd_matches" ("score_id", "rank") WHERE suppressed = FALSE;
CREATE TABLE IF NOT EXISTS "ahoy_visits" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "visit_token" varchar, "visitor_token" varchar, "ip" varchar, "user_agent" text, "referrer" text, "referring_domain" varchar, "landing_page" text, "browser" varchar, "os" varchar, "device_type" varchar, "country" varchar, "region" varchar, "city" varchar, "latitude" float, "longitude" float, "utm_source" varchar, "utm_medium" varchar, "utm_term" varchar, "utm_content" varchar, "utm_campaign" varchar, "app_version" varchar, "os_version" varchar, "platform" varchar, "started_at" datetime(6), "visitor_hash" varchar(64), "visitor_hash_next" varchar(64));
CREATE TABLE IF NOT EXISTS "ahoy_events" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "visit_id" integer, "name" varchar, "properties" text, "time" datetime(6));
CREATE TABLE IF NOT EXISTS "smart_search_usages" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "date" date NOT NULL, "count" integer DEFAULT 0 NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE IF NOT EXISTS "smart_search_queries" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "query" text NOT NULL, "query_type" varchar NOT NULL, "parent_query_id" integer, "ip_hash" varchar(64) NOT NULL, "result_count" integer DEFAULT 0 NOT NULL, "score_ids" text DEFAULT '[]' NOT NULL, "rag_summary" text, "rag_recommendations" text, "response_time_ms" integer, "error" text, "locale" varchar(2) NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_661cf8e500"
FOREIGN KEY ("parent_query_id")
  REFERENCES "smart_search_queries" ("id")
 ON DELETE SET NULL);
CREATE TABLE IF NOT EXISTS "smart_search_feedbacks" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "smart_search_query_id" integer NOT NULL, "ip_hash" varchar(64) NOT NULL, "verdict" varchar NOT NULL, "comment" text, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_5f2a9b86f0"
FOREIGN KEY ("smart_search_query_id")
  REFERENCES "smart_search_queries" ("id")
 ON DELETE CASCADE);
CREATE UNIQUE INDEX "index_active_storage_blobs_on_key" ON "active_storage_blobs" ("key") /*application='Scorebase'*/;
CREATE INDEX "index_active_storage_attachments_on_blob_id" ON "active_storage_attachments" ("blob_id") /*application='Scorebase'*/;
CREATE UNIQUE INDEX "index_active_storage_attachments_uniqueness" ON "active_storage_attachments" ("record_type", "record_id", "name", "blob_id") /*application='Scorebase'*/;
CREATE UNIQUE INDEX "index_active_storage_variant_records_uniqueness" ON "active_storage_variant_records" ("blob_id", "variation_digest") /*application='Scorebase'*/;
CREATE UNIQUE INDEX "index_composer_mappings_on_original_name" ON "composer_mappings" ("original_name");
CREATE INDEX "index_composer_mappings_on_normalized_name" ON "composer_mappings" ("normalized_name");
CREATE UNIQUE INDEX "index_score_pages_on_score_id_and_page_number" ON "score_pages" ("score_id", "page_number");
CREATE UNIQUE INDEX "index_waitlist_signups_on_email" ON "waitlist_signups" ("email");
CREATE INDEX "index_score_page_deletion_logs_on_deleted_at" ON "score_page_deletion_logs" ("deleted_at");
CREATE INDEX "index_score_page_deletion_logs_on_score_id" ON "score_page_deletion_logs" ("score_id");
CREATE UNIQUE INDEX "index_daily_stats_on_date" ON "daily_stats" ("date");
CREATE UNIQUE INDEX "index_ahoy_visits_on_visit_token" ON "ahoy_visits" ("visit_token");
CREATE INDEX "index_ahoy_visits_on_visitor_token_and_started_at" ON "ahoy_visits" ("visitor_token", "started_at");
CREATE INDEX "index_ahoy_visits_on_started_at" ON "ahoy_visits" ("started_at");
CREATE INDEX "index_ahoy_events_on_visit_id" ON "ahoy_events" ("visit_id");
CREATE INDEX "index_ahoy_events_on_name_and_time" ON "ahoy_events" ("name", "time");
CREATE INDEX "index_ahoy_events_on_time" ON "ahoy_events" ("time");
CREATE UNIQUE INDEX "index_smart_search_usages_on_date" ON "smart_search_usages" ("date");
CREATE INDEX "index_smart_search_queries_on_parent_query_id" ON "smart_search_queries" ("parent_query_id");
CREATE INDEX "index_smart_search_queries_on_created_at" ON "smart_search_queries" ("created_at");
CREATE INDEX "index_smart_search_queries_on_ip_hash" ON "smart_search_queries" ("ip_hash");
CREATE UNIQUE INDEX "idx_one_refinement_per_parent" ON "smart_search_queries" ("parent_query_id") WHERE query_type = 'refinement';
CREATE INDEX "idx_normalized_query_created_at" ON "smart_search_queries" (LOWER(TRIM(query)), created_at);
CREATE INDEX "index_smart_search_feedbacks_on_smart_search_query_id" ON "smart_search_feedbacks" ("smart_search_query_id");
CREATE UNIQUE INDEX "idx_one_feedback_per_query_per_visitor" ON "smart_search_feedbacks" ("smart_search_query_id", "ip_hash");
CREATE TRIGGER log_score_page_deletion
      AFTER DELETE ON score_pages
      FOR EACH ROW
      BEGIN
        INSERT INTO score_page_deletion_logs (score_page_id, score_id, page_number, deleted_at, source)
        VALUES (OLD.id, OLD.score_id, OLD.page_number, datetime('now'), 'trigger');
      END;
CREATE VIRTUAL TABLE scores_instruments_fts USING fts5(
        instruments,
        content='',
        tokenize='trigram'
      )
/* scores_instruments_fts(instruments) */;
CREATE VIRTUAL TABLE scores_search_fts USING fts5(
        title,
        composer,
        genre,
        content='',
        tokenize='trigram'
      )
/* scores_search_fts(title,composer,genre) */;
CREATE TABLE IF NOT EXISTS "scores" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "title" varchar, "composer" varchar, "key_signature" varchar, "time_signature" varchar, "num_parts" integer, "genre" text, "tags" text, "complexity" integer, "rating" decimal(3,2), "views" integer DEFAULT 0, "favorites" integer DEFAULT 0, "data_path" varchar, "metadata_path" varchar, "mxl_path" varchar, "pdf_path" varchar, "mid_path" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "source" varchar DEFAULT 'pdmx', "external_url" varchar, "external_id" varchar, "language" varchar, "instruments" varchar, "voicing" varchar, "description" text, "editor" varchar, "license" varchar, "lyrics" text, "cpdl_number" varchar, "posted_date" date, "page_count" integer, "thumbnail_url" varchar, "composer_status" varchar DEFAULT 'pending' NOT NULL, "highest_pitch" varchar, "lowest_pitch" varchar, "ambitus_semitones" integer, "pitch_range_per_part" json, "voice_ranges" json, "tempo_bpm" integer, "tempo_marking" varchar, "duration_seconds" float, "measure_count" integer, "event_count" integer, "note_density" float, "unique_pitches" integer, "accidental_count" integer, "chromatic_ratio" float, "rhythm_distribution" json, "syncopation_level" float, "rhythmic_variety" float, "predominant_rhythm" varchar, "key_confidence" float, "key_correlations" json, "modulations" text, "modulation_count" integer, "harmonic_rhythm" float, "interval_distribution" json, "largest_interval" integer, "stepwise_motion_ratio" float, "melodic_contour" varchar, "melodic_complexity" float, "form_analysis" varchar, "sections_count" integer, "repeats_count" integer, "cadence_types" text, "final_cadence" varchar, "clefs_used" text, "has_dynamics" boolean, "dynamic_range" varchar, "has_articulations" boolean, "has_ornaments" boolean, "has_tempo_changes" boolean, "has_fermatas" boolean, "expression_markings" text, "has_extracted_lyrics" boolean, "extracted_lyrics" text, "syllable_count" integer, "lyrics_language" varchar, "part_names" text, "detected_instruments" text, "instrument_families" text, "has_vocal" boolean, "is_instrumental" boolean, "has_accompaniment" boolean, "texture_type" varchar, "vertical_density" float, "voice_independence" float, "extraction_status" varchar DEFAULT 'pending' NOT NULL, "extraction_error" text, "extracted_at" datetime(6), "music21_version" varchar, "musicxml_source" varchar, "rag_status" varchar DEFAULT 'pending' NOT NULL, "search_text" text, "search_text_generated_at" datetime(6), "indexed_at" datetime(6), "index_version" integer, "period" varchar, "genre_status" varchar DEFAULT 'pending' NOT NULL, "period_status" varchar DEFAULT 'pending' NOT NULL, "instruments_status" varchar DEFAULT 'pending' NOT NULL, "computed_difficulty" integer, "max_chord_span" integer, "tessitura" json, "leap_count" integer, "leaps_per_measure" float, "has_vocal_status" varchar DEFAULT 'pending' NOT NULL, "voicing_status" varchar DEFAULT 'pending' NOT NULL, "chromatic_note_count" integer, "meter_classification" varchar, "beat_count" integer, "has_pedal_marks" boolean, "slur_count" integer, "has_ottava" boolean, "trill_count" integer, "mordent_count" integer, "turn_count" integer, "tremolo_count" integer, "grace_note_count" integer, "arpeggio_mark_count" integer, "modulation_targets" json, "unique_duration_count" integer, "off_beat_count" integer, "chord_count" integer, "interval_count" integer, "stepwise_count" integer, "simultaneous_note_avg" float, "pitch_count" integer, "pitch_class_distribution" json, "texture_variation" float, "avg_chord_span" float, "contrary_motion_ratio" float, "parallel_motion_ratio" float, "oblique_motion_ratio" float, "unique_chord_count" integer, "estimated_tempo_bpm" integer, "estimated_duration_seconds" float, "tempo_referent" float, "total_quarter_length" float, "is_multi_movement" boolean, "pedagogical_grade" varchar, "pedagogical_grade_de" varchar, "grade_status" varchar DEFAULT 'pending' NOT NULL, "grade_source" varchar, "title_search_normalized" varchar, "composer_search_normalized" varchar, "deleted_at" datetime(6), "contributors" json, "main_instrument" varchar, "arrangement_category" varchar, "smd_category" varchar, "brand" varchar, "is_arrangeme" boolean, "price_usd" decimal(8,2), "original_price_usd" decimal(8,2), "review_count" integer, "pitch_range" varchar, "is_interactive" boolean, "preview_image_url" varchar, "artist" varchar, "group_key" varchar, "is_group_representative" boolean, "last_crawled_at" datetime(6));
CREATE INDEX "index_scores_on_key_signature" ON "scores" ("key_signature") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_time_signature" ON "scores" ("time_signature") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_num_parts" ON "scores" ("num_parts") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_complexity" ON "scores" ("complexity") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_rating" ON "scores" ("rating") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_views" ON "scores" ("views") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_composer" ON "scores" ("composer") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_source" ON "scores" ("source") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_external_id" ON "scores" ("external_id") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_voicing" ON "scores" ("voicing") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_smd_category_and_deleted_at" ON "scores" ("smd_category", "deleted_at") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_source_and_last_crawled_at" ON "scores" ("source", "last_crawled_at") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_instruments" ON "scores" ("instruments") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_extraction_status" ON "scores" ("extraction_status") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_ambitus_semitones" ON "scores" ("ambitus_semitones") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_highest_pitch" ON "scores" ("highest_pitch") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_lowest_pitch" ON "scores" ("lowest_pitch") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_duration_seconds" ON "scores" ("duration_seconds") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_tempo_bpm" ON "scores" ("tempo_bpm") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_measure_count" ON "scores" ("measure_count") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_melodic_complexity" ON "scores" ("melodic_complexity") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_has_extracted_lyrics" ON "scores" ("has_extracted_lyrics") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_texture_type" ON "scores" ("texture_type") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_key_confidence" ON "scores" ("key_confidence") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_modulation_count" ON "scores" ("modulation_count") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_rag_status" ON "scores" ("rag_status") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_indexed_at" ON "scores" ("indexed_at") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_period" ON "scores" ("period") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_composer_status" ON "scores" ("composer_status") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_genre" ON "scores" ("genre") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_genre_status" ON "scores" ("genre_status") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_period_status" ON "scores" ("period_status") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_instruments_status" ON "scores" ("instruments_status") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_computed_difficulty" ON "scores" ("computed_difficulty") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_has_vocal" ON "scores" ("has_vocal") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_has_vocal_status" ON "scores" ("has_vocal_status") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_voicing_status" ON "scores" ("voicing_status") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_genre_status_and_lower_genre" ON "scores" (genre_status, LOWER(genre)) /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_event_count" ON "scores" ("event_count") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_chromatic_ratio" ON "scores" ("chromatic_ratio") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_pedagogical_grade" ON "scores" ("pedagogical_grade") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_grade_status" ON "scores" ("grade_status") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_title_search_normalized" ON "scores" ("title_search_normalized") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_composer_search_normalized" ON "scores" ("composer_search_normalized") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_created_at" ON "scores" ("created_at") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_deleted_at" ON "scores" ("deleted_at") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_brand" ON "scores" ("brand") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_is_arrangeme" ON "scores" ("is_arrangeme") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_price_usd" ON "scores" ("price_usd") /*application='Scorebase'*/;
CREATE INDEX "index_scores_active_by_created_at" ON "scores" ("created_at" DESC) WHERE deleted_at IS NULL /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_artist" ON "scores" ("artist") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_group_key" ON "scores" ("group_key") /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_is_group_representative" ON "scores" ("is_group_representative") WHERE is_group_representative = 1 /*application='Scorebase'*/;
CREATE INDEX "index_scores_on_period_and_deleted_at" ON "scores" ("period", "deleted_at") /*application='Scorebase'*/;
CREATE TRIGGER scores_search_fts_ai AFTER INSERT ON scores
      WHEN NEW.deleted_at IS NULL
      BEGIN
        INSERT INTO scores_search_fts(rowid, title, composer, genre)
        VALUES (
          NEW.id,
          COALESCE(LOWER(NEW.title_search_normalized), ''),
          COALESCE(LOWER(NEW.composer_search_normalized), ''),
          COALESCE(LOWER(NEW.genre), '')
        );
      END;
CREATE TRIGGER scores_search_fts_ad AFTER DELETE ON scores
      BEGIN
        INSERT INTO scores_search_fts(scores_search_fts, rowid, title, composer, genre)
        VALUES (
          'delete',
          OLD.id,
          COALESCE(LOWER(OLD.title_search_normalized), ''),
          COALESCE(LOWER(OLD.composer_search_normalized), ''),
          COALESCE(LOWER(OLD.genre), '')
        );
      END;
CREATE TRIGGER scores_search_fts_au AFTER UPDATE ON scores
      BEGIN
        INSERT INTO scores_search_fts(scores_search_fts, rowid, title, composer, genre)
        SELECT 'delete', OLD.id,
               COALESCE(LOWER(OLD.title_search_normalized), ''),
               COALESCE(LOWER(OLD.composer_search_normalized), ''),
               COALESCE(LOWER(OLD.genre), '')
        WHERE OLD.deleted_at IS NULL;

        INSERT INTO scores_search_fts(rowid, title, composer, genre)
        SELECT NEW.id,
               COALESCE(LOWER(NEW.title_search_normalized), ''),
               COALESCE(LOWER(NEW.composer_search_normalized), ''),
               COALESCE(LOWER(NEW.genre), '')
        WHERE NEW.deleted_at IS NULL;
      END;
CREATE TRIGGER scores_instruments_fts_ai AFTER INSERT ON scores
      WHEN NEW.instruments IS NOT NULL AND NEW.instruments != '' AND NEW.deleted_at IS NULL
      BEGIN
        INSERT INTO scores_instruments_fts(rowid, instruments)
        VALUES (NEW.id, LOWER(NEW.instruments));
      END;
CREATE TRIGGER scores_instruments_fts_ad AFTER DELETE ON scores
      WHEN OLD.instruments IS NOT NULL AND OLD.instruments != ''
      BEGIN
        INSERT INTO scores_instruments_fts(scores_instruments_fts, rowid, instruments)
        VALUES ('delete', OLD.id, LOWER(OLD.instruments));
      END;
CREATE TRIGGER scores_instruments_fts_au AFTER UPDATE ON scores
      BEGIN
        INSERT INTO scores_instruments_fts(scores_instruments_fts, rowid, instruments)
        SELECT 'delete', OLD.id, LOWER(OLD.instruments)
        WHERE OLD.instruments IS NOT NULL
          AND OLD.instruments != ''
          AND OLD.deleted_at IS NULL;

        INSERT INTO scores_instruments_fts(rowid, instruments)
        SELECT NEW.id, LOWER(NEW.instruments)
        WHERE NEW.instruments IS NOT NULL
          AND NEW.instruments != ''
          AND NEW.deleted_at IS NULL;
      END;
INSERT INTO "schema_migrations" (version) VALUES
('20260720120000'),
('20260719110000'),
('20260718100000'),
('20260716160001'),
('20260716160000'),
('20260520104043'),
('20260519141638'),
('20260517180718'),
('20260517180654'),
('20260517143000'),
('20260429153719'),
('20260428102431'),
('20260428081717'),
('20260428064428'),
('20260205105535'),
('20260201203016'),
('20260201090100'),
('20260131210236'),
('20260131124536'),
('20260130134622'),
('20260130124957'),
('20260129142312'),
('20260129140215'),
('20260129111339'),
('20260128191452'),
('20260121085101'),
('20260121084045'),
('20260120131749'),
('20260115212931'),
('20260115172125'),
('20260113085527'),
('20260112150307'),
('20260110213300'),
('20260109201317'),
('20260109200255'),
('20260109192624'),
('20260109160000'),
('20260109150000'),
('20260109113305'),
('20260109102058'),
('20260108204206'),
('20260108144459'),
('20260108101724'),
('20260107223103'),
('20260107222031'),
('20260105142840'),
('20260105132745'),
('20260105131517'),
('20260105110533'),
('20251230153036'),
('20251224112044'),
('20251223095424'),
('20251223081909'),
('20251220152603'),
('20251218200604'),
('20251216103617'),
('20251215154524'),
('20251215150249'),
('20251215135007'),
('20251214115527'),
('20251213131224'),
('20251213102215'),
('20251212095552'),
('20251211091645'),
('20251211091153'),
('20251211085646'),
('20251210233957'),
('20251210233347'),
('20251210223327'),
('20251209194433');

