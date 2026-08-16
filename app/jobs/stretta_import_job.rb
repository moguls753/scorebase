# frozen_string_literal: true

# Fetches and writes a batch of Stretta products.
class StrettaImportJob < ApplicationJob
  queue_as :default

  # Shared with the refresh and new-release jobs: each holds its own client, so an
  # overlap doubles the request rate at Stretta and can collide with the 2am pass.
  limits_concurrency to: 1, key: "stretta-music.de", group: "stretta", duration: 12.hours

  def perform(handles, client: nil, regroup: false)
    client ||= Stretta::Client.new
    importer = Stretta::Importer.new(regroup: regroup)

    stats = importer.import(client.products(handles))
    logger.info "[StrettaImport] #{handles.size} handles -> #{stats}"
    stats
  end
end
