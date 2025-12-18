# Override Active Storage S3 service to use custom CDN domain for public URLs
# This is needed for Cloudflare R2 with a custom domain (cdn.scorebase.org)
#
# The public_url option is set in config/storage.yml under upload:
#   cloudflare:
#     service: S3
#     public: true
#     upload:
#       public_url: https://cdn.scorebase.org

Rails.application.config.after_initialize do
  ActiveStorage::Service::S3Service.prepend(Module.new do
    def public_url(key, **)
      if public? && upload_options[:public_url]
        "#{upload_options[:public_url]}/#{key}"
      else
        super
      end
    end
  end)
end
