class VisitorHash
  def self.period_key(date)
    "#{date.year}H#{date.month <= 6 ? 1 : 2}"
  end

  def self.next_period_date(date)
    date.month <= 6 ? Date.new(date.year, 7, 1) : Date.new(date.year + 1, 1, 1)
  end

  def self.salt_for(date)
    Digest::SHA256.hexdigest(
      "scorebase_visitor|#{period_key(date)}|#{Rails.application.secret_key_base}"
    )
  end

  def self.from(ip:, user_agent:, date: Date.current)
    return nil if ip.blank?

    Digest::SHA256.hexdigest("#{salt_for(date)}|#{ip}|#{user_agent}")
  end

  def self.from_next(ip:, user_agent:, date: Date.current)
    from(ip: ip, user_agent: user_agent, date: next_period_date(date))
  end
end
