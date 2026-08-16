# frozen_string_literal: true

# Daily price and availability rotation over the Stretta catalogue
# (docs/stretta-import-plan.md §12).
#
# `updatedAt` is useless as a delta signal — 100% of the catalogue carries a
# July/August 2026 timestamp from the shop migration — so this rotates by our own
# last_crawled_at, exactly like SmdRefreshJob.
class StrettaRefreshJob < ApplicationJob
  queue_as :default

  limits_concurrency to: 1, key: "stretta-music.de", group: "stretta", duration: 12.hours

  BATCH_SIZE = 500
  PRICE_FIELDS = { price_eur: :price, original_price_eur: :compare_at_price,
                   available_for_sale: :available_for_sale }.freeze

  def perform(limit: 5000, client: nil)
    client ||= Stretta::Client.new
    handles = Score.where(source: "stretta").order(Arel.sql("last_crawled_at"), :id).limit(limit).pluck(:external_id)
    return { checked: 0 } if handles.empty?

    stats = { checked: 0, updated: 0, unchanged: 0, missing: 0 }
    seen = []

    client.products(handles).each_slice(BATCH_SIZE) do |batch|
      stats[:checked] += batch.size
      seen.concat(batch.map { |product| product[:handle].to_s })
      apply(batch, stats)
    end

    # Every handle we asked about, not just the ones that answered. 8.2% of ids are
    # dead: stamping only the answers leaves those with the oldest timestamp, so the
    # next run selects them again and the rotation wedges at the head forever.
    Score.where(source: "stretta", external_id: handles).update_all(last_crawled_at: Time.current)
    stats[:missing] = handles.size - seen.uniq.size
    logger.info "[StrettaRefresh] #{stats}"
    stats
  end

  private

  def apply(products, stats)
    handles = products.map { |product| product[:handle].to_s }
    stored = Score.where(source: "stretta", external_id: handles)
                  .pluck(:external_id, *PRICE_FIELDS.keys)
                  .to_h { |external_id, *values| [ external_id, PRICE_FIELDS.keys.zip(values).to_h ] }

    products.each do |product|
      current = stored[product[:handle].to_s]
      next unless current

      wanted = PRICE_FIELDS.transform_values { |source_key| product[source_key] }
      if same?(current, wanted)
        stats[:unchanged] += 1
        next
      end

      Score.where(source: "stretta", external_id: product[:handle].to_s).update_all(wanted)
      stats[:updated] += 1
    end
  end

  # The stored prices come back as BigDecimal, the API's as Float.
  def same?(current, wanted)
    current.all? do |column, value|
      value.is_a?(Numeric) || wanted[column].is_a?(Numeric) ? value&.to_f == wanted[column]&.to_f : value == wanted[column]
    end
  end
end
