class SmartSearchUsage < ApplicationRecord
  DEFAULT_CAP = 20

  # Returns the charged date on success, nil at cap. Callers must hand the
  # returned date back to refund! — a request that straddles UTC midnight
  # would otherwise refund the wrong row.
  def self.try_consume!(date: utc_today, cap: DEFAULT_CAP)
    create_or_find_by(date: date)
    rows = where(date: date).where("count < ?", cap).update_all("count = count + 1")
    rows > 0 ? date : nil
  end

  def self.refund!(charged_date)
    return if charged_date.nil?
    where(date: charged_date).where("count > 0").update_all("count = count - 1")
  end

  def self.utc_today
    Time.current.utc.to_date
  end
end
