# frozen_string_literal: true

require "active_storage/service/s3_service"

module ActiveStorage
  class Service::CloudflareR2Service < Service::S3Service
    attr_reader :public_url_host

    def initialize(bucket:, upload: {}, public: false, **options)
      @public_url_host = upload.delete(:public_url)
      super
    end

    private

    def public_url(key, **)
      if public_url_host
        "#{public_url_host}/#{key}"
      else
        super
      end
    end
  end
end
