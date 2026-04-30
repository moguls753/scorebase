# == Schema Information
#
# Table name: ahoy_events
#
#  id         :integer          not null, primary key
#  name       :string
#  properties :text
#  time       :datetime
#  visit_id   :integer
#
# Indexes
#
#  index_ahoy_events_on_name_and_time  (name,time)
#  index_ahoy_events_on_time           (time)
#  index_ahoy_events_on_visit_id       (visit_id)
#
class Ahoy::Event < ApplicationRecord
  include Ahoy::QueryMethods

  self.table_name = "ahoy_events"

  belongs_to :visit

  serialize :properties, coder: JSON
end
