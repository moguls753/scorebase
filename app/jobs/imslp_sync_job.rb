class ImslpSyncJob < ApplicationJob
  queue_as :default

  # IMSLP imports are very long-running, limit retries
  retry_on StandardError, wait: 10.minutes, attempts: 2
  discard_on ImslpImporter::RateLimitError  # Don't retry rate limits

  def perform(limit: nil, resume: true, start_offset: 0)
    Rails.logger.info "Starting IMSLP sync job (resume: #{resume}, offset: #{start_offset})..."

    importer = ImslpImporter.new(
      limit: limit,
      resume: resume,
      start_offset: start_offset
    )
    result = importer.import!

    Rails.logger.info "IMSLP sync complete: #{result.inspect}"

    result
  end
end
