class CpdlSyncJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 5.minutes, attempts: 3

  def perform(limit: nil, base_url: CpdlImporter::BASE_URL)
    Rails.logger.info "Starting CPDL sync (limit: #{limit || 'none'}, source: #{base_url})"
    result = CpdlImporter.new(limit: limit, base_url: base_url).import!
    Rails.logger.info "CPDL sync complete: #{result.inspect}"
    result
  end
end
