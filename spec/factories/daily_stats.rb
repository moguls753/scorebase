# == Schema Information
#
# Table name: daily_stats
#
#  id                      :integer          not null, primary key
#  countries               :json
#  date                    :date
#  devices                 :json
#  human_converting_visits :integer
#  human_visits            :integer
#  paths                   :json
#  referrers               :json
#  smd_clicks_by_score     :json
#  visits                  :integer          default(0)
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#
# Indexes
#
#  index_daily_stats_on_date  (date) UNIQUE
#
FactoryBot.define do
  factory :daily_stat do
    date { Date.current }
    visits { 200 }
    smd_clicks_by_score { {} }
    countries { {} }
    referrers { {} }
    paths { {} }
    devices { {} }
  end
end
