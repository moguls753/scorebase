class SmartSearchQuota
  PER_IP_DAILY_LIMIT = 10

  # Returns the charged date on success, or :per_ip_limit / :site_limit
  # if the corresponding cap is hit. Hand the charged date to refund!
  # if downstream work fails.
  def self.try_consume!(ip_hash:)
    return :per_ip_limit if SmartSearchQuery.recent_ip_count(ip_hash) >= PER_IP_DAILY_LIMIT
    SmartSearchUsage.try_consume! || :site_limit
  end

  def self.refund!(charged_date)
    SmartSearchUsage.refund!(charged_date)
  end
end
