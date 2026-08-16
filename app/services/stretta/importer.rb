# frozen_string_literal: true

# Writes classified Stretta products into `scores` (docs/stretta-import-plan.md §3).
module Stretta
  class Importer
    BATCH_SIZE = 500

    # Ownership line, not a completeness line: columns another job owns (composer,
    # pedagogical_grade, rag_status, is_group_representative) are excluded so a
    # resync can't undo their work — see docs/stretta-implementation-notes.md
    # ("Wer welche Spalte besitzt") for the group_key exception and the full
    # reasoning. deleted_at is excluded too: Avo's soft_delete! is a deliberate
    # admin decision, not something a resync should silently reverse.
    #
    # last_crawled_at is different — it's written by this same import, just not
    # here: it changes on every run, and Rails only skips updated_at when nothing
    # in UPDATABLE differs, so including it would restamp updated_at on every row
    # and poison the sitemap's lastmod.
    UPDATABLE = %i[
      title title_search_normalized work_key partner_slug thumbnail_url page_count
      price_eur original_price_eur available_for_sale stretta_metadata
      instruments instruments_status voicing voicing_status has_vocal has_vocal_status
      group_rank smd_category
    ].freeze

    # group_key is derived like the rest but deliberately not updatable: a new key
    # moves a row between groups, and which sibling is visible then has to be
    # decided again by BackfillGroupKeysJob. Only pass regroup: true when the
    # keying rule itself changed, and reassign representatives afterwards.
    def initialize(regroup: false, mapper: nil, logger: Rails.logger)
      @update = regroup ? UPDATABLE + %i[group_key] : UPDATABLE
      @mapper = mapper || ProductMapper.new(composer_index: composer_index)
      @logger = logger
      @stats = Hash.new(0)
    end

    attr_reader :stats

    # Products as Stretta::Client yields them.
    def import(products)
      products.each_slice(BATCH_SIZE) do |batch|
        rows = batch.filter_map { |product| row_for(product) }
        write(rows)
      end
      @stats
    end

    private

    # One query instead of one per row: 21k mappings against 1.2M products.
    def composer_index
      ComposerMapping.normalizable.pluck(:original_name, :normalized_name).to_h
    end

    def row_for(product)
      result = Classifier.classify(product)
      @stats[result.reason] += 1
      return nil unless result.accepted?

      attributes = @mapper.call(product, classification_reason: result.reason)
      if attributes.nil?
        @stats[:unmappable] += 1
        return nil
      end

      attributes
    end

    # A handle repeated inside one batch would make SQLite refuse the statement
    # ("ON CONFLICT DO UPDATE command does not affect row a second time").
    def write(rows)
      rows = rows.uniq { |row| row[:external_id] }
      return if rows.empty?

      Score.upsert_all(
        rows,
        unique_by: %i[source external_id],
        update_only: @update,
        record_timestamps: true
      )
      stamp_crawled(rows)
      @stats[:written] += rows.size
    end

    # Separate and untimestamped: this records when we fetched, which is not a change
    # to the score and must not read as one.
    def stamp_crawled(rows)
      Score.where(source: "stretta", external_id: rows.map { |row| row[:external_id] })
           .update_all(last_crawled_at: Time.current)
    end
  end
end
