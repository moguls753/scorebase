# == Schema Information
#
# Table name: score_pages
#
#  id          :integer          not null, primary key
#  page_number :integer          not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  score_id    :integer          not null
#
# Indexes
#
#  index_score_pages_on_score_id_and_page_number  (score_id,page_number) UNIQUE
#
# Foreign Keys
#
#  score_id  (score_id => scores.id) ON DELETE => cascade
#
class ScorePage < ApplicationRecord
  belongs_to :score

  has_one_attached :image

  validates :page_number, presence: true,
                          numericality: { only_integer: true, greater_than: 0 },
                          uniqueness: { scope: :score_id }

  scope :ordered, -> { order(:page_number) }
end
