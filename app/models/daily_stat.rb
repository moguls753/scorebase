# == Schema Information
#
# Table name: daily_stats
#
#  id         :integer          not null, primary key
#  date       :date
#  smd_clicks :integer          default(0)
#  visits     :integer          default(0)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_daily_stats_on_date  (date) UNIQUE
#
class DailyStat < ApplicationRecord
  def self.track_visit!
    today = find_or_create_by(date: Date.current)
    today.increment!(:visits)
  end

  def self.track_smd_click!
    today = find_or_create_by(date: Date.current)
    today.increment!(:smd_clicks)
  end
end
