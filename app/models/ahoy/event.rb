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

  PAGE = "json_extract(ahoy_events.properties, '$.page')".freeze
  # Without the instr guard a non-score path parses from character 8 and can cast to a real score id.
  PAGE_SCORE_ID = <<~SQL.squish.freeze
    CASE WHEN instr(#{PAGE}, '/scores/') > 0
         THEN CAST(substr(#{PAGE}, instr(#{PAGE}, '/scores/') + 8) AS INTEGER) END
  SQL
  private_constant :PAGE_SCORE_ID

  scope :on_partner_score_page, ->(source) {
    joins("JOIN scores ON scores.id = #{PAGE_SCORE_ID}").where(scores: { source: source })
  }

  # One event name per partner rather than a shared one with a property: the
  # historical "SMD click" rows stay readable without a compatibility branch.
  CLICK_EVENTS = { "smd" => "SMD click", "stretta" => "Stretta click" }.freeze
end
