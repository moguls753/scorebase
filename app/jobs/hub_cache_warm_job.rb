# frozen_string_literal: true

# Pre-warms hub page caches. Run daily via cron.
#
# The actual building logic lives in HubDataBuilder service.
# This job just triggers the warm and handles any errors gracefully.
#
class HubCacheWarmJob < ApplicationJob
  queue_as :default

  def perform
    HubDataBuilder.warm_all
  rescue => e
    Rails.logger.error "[HubCacheWarmJob] Failed: #{e.message}"
    raise # Re-raise so job failure is tracked
  end
end
