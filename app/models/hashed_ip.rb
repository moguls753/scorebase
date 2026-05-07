class HashedIp
  SALT = Digest::SHA256.hexdigest("smart_search_ip|#{Rails.application.secret_key_base}").freeze

  def self.from(ip)
    Digest::SHA256.hexdigest("#{SALT}|#{ip}")
  end
end
