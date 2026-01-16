class CpdlSyncJob < ApplicationJob
  queue_as :default

  # Limit retries - full sync can take a while
  retry_on StandardError, wait: 5.minutes, attempts: 3

  def perform(limit: nil)
    Rails.logger.info "Starting CPDL sync job (limit: #{limit || 'none'})..."

    importer = CpdlImporter.new(limit: limit)
    result = importer.import!

    Rails.logger.info "CPDL sync complete: #{result.inspect}"

    result
  end
end
