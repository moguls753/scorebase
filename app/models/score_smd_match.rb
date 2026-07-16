# == Schema Information
#
# Table name: score_smd_matches
#
#  id           :integer          not null, primary key
#  rank         :integer          not null
#  suppressed   :boolean          default(FALSE), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  score_id     :integer          not null
#  smd_score_id :integer          not null
#
# Indexes
#
#  index_score_smd_matches_on_score_id                   (score_id)
#  index_score_smd_matches_on_score_id_and_rank          (score_id,rank) UNIQUE WHERE suppressed = FALSE
#  index_score_smd_matches_on_score_id_and_smd_score_id  (score_id,smd_score_id) UNIQUE
#  index_score_smd_matches_on_smd_score_id               (smd_score_id)
#
# Foreign Keys
#
#  score_id      (score_id => scores.id) ON DELETE => cascade
#  smd_score_id  (smd_score_id => scores.id) ON DELETE => cascade
#
class ScoreSmdMatch < ApplicationRecord
  belongs_to :score
  belongs_to :smd_score, class_name: "Score"

  validates :rank, inclusion: { in: 1..SmdMatchFinder::MAX_MATCHES }
end
