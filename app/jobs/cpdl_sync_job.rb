class CpdlSyncJob < ApplicationJob
  queue_as :default

  # Limit retries - full sync can take a while
  retry_on StandardError, wait: 5.minutes, attempts: 3

  def perform(limit: nil, base_url: nil)
    source = base_url || CpdlImporter::BASE_URL
    Rails.logger.info "Starting CPDL sync job (limit: #{limit || 'none'}, source: #{source})"

    importer = if base_url
      CpdlImporter.new(limit: limit, base_url: base_url, http_client: CloudflareBypassClient.new)
    else
      CpdlImporter.new(limit: limit)
    end
    result = importer.import!

    Rails.logger.info "CPDL sync complete: #{result.inspect}"

    result
  end
end
