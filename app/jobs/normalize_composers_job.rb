# frozen_string_literal: true

# Normalizes composer names using LLM.
# No prerequisites - this runs first in the pipeline.
#
# Usage:
#   NormalizeComposersJob.perform_later
#   NormalizeComposersJob.perform_later(limit: 500)
#   NormalizeComposersJob.perform_later(limit: nil)  # process all
#
class NormalizeComposersJob < ApplicationJob
  queue_as :normalization

  def perform(limit: nil)
    ComposerNormalizer.new(limit: limit).normalize!
  end
end
