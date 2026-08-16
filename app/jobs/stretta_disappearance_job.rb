# frozen_string_literal: true

# Soft-deletes Stretta rows whose product is gone (docs/stretta-import-plan.md §12).
#
# Neither signal is proof on its own: 8.2% of sitemap ids are dead while the
# product still sells, and the sitemap is itself incomplete. So absence from the
# sitemap is only a suspicion, and the API decides.
#
# NOT scheduled, deliberately. It needs the CloudflareBypass accessory for the
# sitemap harvest, it holds every live handle in memory at once, and it soft-deletes.
# Run it by hand and read the stats before believing them.
class StrettaDisappearanceJob < ApplicationJob
  queue_as :default

  limits_concurrency to: 1, key: "stretta-music.de", group: "stretta", duration: 12.hours

  # A run that would remove more than this is reporting a broken harvest, not a
  # shrinking catalogue. Abort rather than empty the shelf.
  MAX_DELETION_SHARE = 0.01

  class TooManyDeletions < StandardError; end

  def perform(client: nil, harvester: nil)
    client ||= Stretta::Client.new
    harvester ||= Stretta::SitemapHarvester.new

    live = Set.new
    harvester.each_handle { |handle| live << handle }
    held = Score.where(source: "stretta", deleted_at: nil).pluck(:external_id).to_set
    suspects = (held - live).to_a

    confirmed = confirm(client, suspects)
    guard(confirmed.size, held.size)

    Score.where(source: "stretta", external_id: confirmed).update_all(deleted_at: Time.current)
    stats = { held: held.size, suspects: suspects.size, deleted: confirmed.size }
    logger.info "[StrettaDisappearance] #{stats}"
    stats
  end

  private

  # Still answered by the API, so it exists and the sitemap is simply incomplete.
  def confirm(client, suspects)
    return [] if suspects.empty?

    alive = client.products(suspects).map { |product| product[:handle].to_s }.to_set
    suspects.reject { |handle| alive.include?(handle) }
  end

  def guard(deletions, held)
    return if held.zero? || deletions <= held * MAX_DELETION_SHARE

    raise TooManyDeletions, "#{deletions} of #{held} rows would be deleted — refusing"
  end
end
