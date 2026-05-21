class ImslpSyncJob < ApplicationJob
  queue_as :default

  # IMSLP imports are very long-running; limit retries.
  retry_on StandardError, wait: 10.minutes, attempts: 2
  discard_on ImslpImporter::RateLimitError

  def perform
    Rails.logger.info "Starting IMSLP priority sync job..."
    result = ImslpImporter.new.import_priority!
    Rails.logger.info "IMSLP sync complete: #{result.inspect}"
    result
  end
end
