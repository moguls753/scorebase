class CpdlSyncJob < ApplicationJob
  queue_as :default

  # Limit retries - full sync can take a while
  retry_on StandardError, wait: 5.minutes, attempts: 3

  def perform(limit: nil, resume: true)
    Rails.logger.info "Starting CPDL sync job (resume: #{resume})..."

    importer = CpdlImporter.new(limit: limit, resume: resume)
    result = importer.import!

    Rails.logger.info "CPDL sync complete: #{result.inspect}"

    result
  end
end
