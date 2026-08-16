# frozen_string_literal: true

# Weekly pass over newly created Stretta products (docs/stretta-import-plan.md §12).
#
# products(sortKey: CREATED_AT) is safe here where a full pass is not: the weekly
# arrival rate stays far below the connection's 25,000-element cap.
#
# The stopping rule is "we already hold these", not a date. A date watermark would
# have to compare Stretta's createdAt against something we store, and our own
# created_at records when we imported a row — importing a backlog today would set it
# to today and permanently hide everything Stretta created last week.
class StrettaNewReleasesJob < ApplicationJob
  queue_as :default

  limits_concurrency to: 1, key: "stretta-music.de", group: "stretta", duration: 12.hours

  # Walking newest-first, this many already-held products in a row means we have
  # reached the part of the catalogue the last run covered.
  KNOWN_RUN_LENGTH = 250

  def perform(client: nil)
    client ||= Stretta::Client.new
    fresh = []
    known_run = 0

    client.newest_first.each do |product|
      if held?(product[:handle])
        known_run += 1
        break if known_run >= KNOWN_RUN_LENGTH
      else
        known_run = 0
        fresh << product
      end
    end

    stats = fresh.any? ? Stretta::Importer.new.import(fresh) : { seen: 0 }
    logger.info "[StrettaNewReleases] #{fresh.size} new -> #{stats}"
    stats
  end

  private

  def held?(handle)
    Score.exists?(source: "stretta", external_id: handle.to_s)
  end
end
