# frozen_string_literal: true

# == Schema Information
#
# Table name: app_settings
#
#  id         :integer          not null, primary key
#  key        :string           not null
#  value      :json
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_app_settings_on_key  (key) UNIQUE
#
class AppSetting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  def self.get(key)
    find_by(key: key)&.value
  end

  def self.fetch(key, default = nil)
    get(key) || default
  end

  def self.set(key, value)
    setting = find_or_initialize_by(key: key)
    setting.update!(value: value)
    value
  end
end
