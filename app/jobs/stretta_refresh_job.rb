# frozen_string_literal: true

# Rotate by our own crawl time; Stretta's updatedAt isn't a reliable delta signal.
class StrettaRefreshJob < ApplicationJob
  queue_as :default

  limits_concurrency to: 1, key: "stretta-music.de", group: "stretta", duration: 12.hours

  PRICE_FIELDS = { price_eur: :price, original_price_eur: :compare_at_price,
                   available_for_sale: :available_for_sale }.freeze

  def perform(limit: 5000, client: nil)
    client ||= Stretta::Client.new
    scores = Score.active.where(source: "stretta")
    handles = scores.order(:last_crawled_at, :id).limit(limit).pluck(:external_id)
    stats = { checked: 0, updated: 0, unchanged: 0, missing: 0, metadata_changed: 0 }

    client.each_product_batch(handles) do |batch, products|
      rows = scores.where(external_id: batch)
      by_handle = products.index_by { |product| product.fetch(:handle) }
      Score.transaction do
        rows.select(:id, :external_id, :stretta_metadata, *PRICE_FIELDS.keys).each do |score|
          product = by_handle[score.external_id]
          refresh(score, product, stats) if product
        end
        # A confirmed miss rotates too. On a failed request the client never yields.
        rows.update_all(last_crawled_at: Time.current)
      end
      stats[:checked] += products.size
      stats[:missing] += batch.size - products.size
    end
    stats[:failed] = handles.size - stats[:checked] - stats[:missing]
    logger.info "[StrettaRefresh] #{stats}"
    stats
  end

  private

  def refresh(score, product, stats)
    changes = PRICE_FIELDS.transform_values { |key| product[key] }.reject { |field, value| score.public_send(field) == value }
    stats[changes.empty? ? :unchanged : :updated] += 1

    current = score.stretta_metadata || {}
    supplied = product.slice(*Stretta::Product::SEARCH_FIELDS).stringify_keys
    metadata = current.except(*supplied.keys).merge(supplied.compact_blank)
    if metadata != current
      changes.merge!(stretta_metadata: metadata, updated_at: Time.current)
      stats[:metadata_changed] += 1
    end
    score.update_columns(changes) if changes.any?
  end
end
