# == Schema Information
#
# Table name: scores
#
#  id                         :integer          not null, primary key
#  accidental_count           :integer
#  ambitus_semitones          :integer
#  arpeggio_mark_count        :integer
#  avg_chord_span             :float
#  beat_count                 :integer
#  cadence_types              :text
#  chord_count                :integer
#  chromatic_note_count       :integer
#  chromatic_ratio            :float
#  clefs_used                 :text
#  complexity                 :integer
#  composer                   :string
#  composer_normalized        :string
#  composer_status            :string           default("pending"), not null
#  computed_difficulty        :integer
#  contrary_motion_ratio      :float
#  cpdl_number                :string
#  data_path                  :string
#  description                :text
#  detected_instruments       :text
#  duration_seconds           :float
#  dynamic_range              :string
#  editor                     :string
#  estimated_duration_seconds :float
#  estimated_tempo_bpm        :integer
#  event_count                :integer
#  expression_markings        :text
#  external_url               :string
#  extracted_at               :datetime
#  extracted_lyrics           :text
#  extraction_error           :text
#  extraction_status          :string           default("pending"), not null
#  favorites                  :integer          default(0)
#  final_cadence              :string
#  form_analysis              :string
#  genre                      :text
#  genre_status               :string           default("pending"), not null
#  grace_note_count           :integer
#  grade_source               :string
#  grade_status               :string           default("pending"), not null
#  harmonic_rhythm            :float
#  has_accompaniment          :boolean
#  has_articulations          :boolean
#  has_dynamics               :boolean
#  has_extracted_lyrics       :boolean
#  has_fermatas               :boolean
#  has_ornaments              :boolean
#  has_ottava                 :boolean
#  has_pedal_marks            :boolean
#  has_tempo_changes          :boolean
#  has_vocal                  :boolean
#  has_vocal_status           :string           default("pending"), not null
#  highest_pitch              :string
#  index_version              :integer
#  indexed_at                 :datetime
#  instrument_families        :text
#  instruments                :string
#  instruments_status         :string           default("pending"), not null
#  interval_count             :integer
#  interval_distribution      :json
#  is_instrumental            :boolean
#  is_multi_movement          :boolean
#  key_confidence             :float
#  key_correlations           :json
#  key_signature              :string
#  language                   :string
#  largest_interval           :integer
#  leap_count                 :integer
#  leaps_per_measure          :float
#  license                    :string
#  lowest_pitch               :string
#  lyrics                     :text
#  lyrics_language            :string
#  max_chord_span             :integer
#  measure_count              :integer
#  melodic_complexity         :float
#  melodic_contour            :string
#  metadata_path              :string
#  meter_classification       :string
#  mid_path                   :string
#  modulation_count           :integer
#  modulation_targets         :json
#  modulations                :text
#  mordent_count              :integer
#  music21_version            :string
#  musicxml_source            :string
#  mxl_path                   :string
#  note_density               :float
#  num_parts                  :integer
#  oblique_motion_ratio       :float
#  off_beat_count             :integer
#  page_count                 :integer
#  parallel_motion_ratio      :float
#  part_names                 :text
#  pdf_path                   :string
#  pedagogical_grade          :string
#  pedagogical_grade_de       :string
#  period                     :string
#  period_status              :string           default("pending"), not null
#  pitch_class_distribution   :json
#  pitch_count                :integer
#  pitch_range_per_part       :json
#  posted_date                :date
#  predominant_rhythm         :string
#  rag_status                 :string           default("pending"), not null
#  rating                     :decimal(3, 2)
#  repeats_count              :integer
#  rhythm_distribution        :json
#  rhythmic_variety           :float
#  search_text                :text
#  search_text_generated_at   :datetime
#  sections_count             :integer
#  simultaneous_note_avg      :float
#  slur_count                 :integer
#  source                     :string           default("pdmx")
#  stepwise_count             :integer
#  stepwise_motion_ratio      :float
#  syllable_count             :integer
#  syncopation_level          :float
#  tags                       :text
#  tempo_bpm                  :integer
#  tempo_marking              :string
#  tempo_referent             :float
#  tessitura                  :json
#  texture_type               :string
#  texture_variation          :float
#  thumbnail_url              :string
#  time_signature             :string
#  title                      :string
#  title_normalized           :string
#  total_quarter_length       :float
#  tremolo_count              :integer
#  trill_count                :integer
#  turn_count                 :integer
#  unique_chord_count         :integer
#  unique_duration_count      :integer
#  unique_pitches             :integer
#  vertical_density           :float
#  views                      :integer          default(0)
#  voice_independence         :float
#  voice_ranges               :json
#  voicing                    :string
#  voicing_status             :string           default("pending"), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  external_id                :string
#
# Indexes
#
#  index_scores_on_ambitus_semitones             (ambitus_semitones)
#  index_scores_on_chromatic_ratio               (chromatic_ratio)
#  index_scores_on_complexity                    (complexity)
#  index_scores_on_composer                      (composer)
#  index_scores_on_composer_normalized           (composer_normalized)
#  index_scores_on_composer_status               (composer_status)
#  index_scores_on_computed_difficulty           (computed_difficulty)
#  index_scores_on_duration_seconds              (duration_seconds)
#  index_scores_on_event_count                   (event_count)
#  index_scores_on_external_id                   (external_id)
#  index_scores_on_extraction_status             (extraction_status)
#  index_scores_on_genre                         (genre)
#  index_scores_on_genre_status                  (genre_status)
#  index_scores_on_genre_status_and_lower_genre  (genre_status, LOWER(genre))
#  index_scores_on_grade_status                  (grade_status)
#  index_scores_on_has_extracted_lyrics          (has_extracted_lyrics)
#  index_scores_on_has_vocal                     (has_vocal)
#  index_scores_on_has_vocal_status              (has_vocal_status)
#  index_scores_on_highest_pitch                 (highest_pitch)
#  index_scores_on_indexed_at                    (indexed_at)
#  index_scores_on_instruments                   (instruments)
#  index_scores_on_instruments_status            (instruments_status)
#  index_scores_on_key_confidence                (key_confidence)
#  index_scores_on_key_signature                 (key_signature)
#  index_scores_on_lowest_pitch                  (lowest_pitch)
#  index_scores_on_measure_count                 (measure_count)
#  index_scores_on_melodic_complexity            (melodic_complexity)
#  index_scores_on_modulation_count              (modulation_count)
#  index_scores_on_num_parts                     (num_parts)
#  index_scores_on_pedagogical_grade             (pedagogical_grade)
#  index_scores_on_period                        (period)
#  index_scores_on_period_status                 (period_status)
#  index_scores_on_rag_status                    (rag_status)
#  index_scores_on_rating                        (rating)
#  index_scores_on_source                        (source)
#  index_scores_on_tempo_bpm                     (tempo_bpm)
#  index_scores_on_texture_type                  (texture_type)
#  index_scores_on_time_signature                (time_signature)
#  index_scores_on_title_normalized              (title_normalized)
#  index_scores_on_views                         (views)
#  index_scores_on_voicing                       (voicing)
#  index_scores_on_voicing_status                (voicing_status)
#
FactoryBot.define do
  factory :score do
    sequence(:title) { |n| "Test Score #{n}" }
    sequence(:data_path) { |n| "scores/test_#{n}/score.musicxml" }
    source { "pdmx" }
    composer { "Bach, Johann Sebastian" }

    trait :pdmx do
      source { "pdmx" }
      pdf_path { "./pdf/test.pdf" }
      mxl_path { "./mxl/test.mxl" }
      mid_path { "./mid/test.mid" }
    end

    trait :cpdl do
      source { "cpdl" }
      external_id { "12345" }
    end

    trait :imslp do
      source { "imslp" }
      external_id { "67890" }
    end

    trait :with_pdf do
      pdf_path { "test.pdf" }
    end

    trait :with_thumbnail_url do
      thumbnail_url { "https://example.com/thumb.png" }
    end
  end
end
