# == Schema Information
#
# Table name: score_stretta_matches
#
#  id               :integer          not null, primary key
#  rank             :integer          not null
#  suppressed       :boolean          default(FALSE), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  score_id         :integer          not null
#  stretta_score_id :integer          not null
#
# Indexes
#
#  index_score_stretta_matches_on_score_id                       (score_id)
#  index_score_stretta_matches_on_score_id_and_rank              (score_id,rank) UNIQUE WHERE suppressed = FALSE
#  index_score_stretta_matches_on_score_id_and_stretta_score_id  (score_id,stretta_score_id) UNIQUE
#  index_score_stretta_matches_on_stretta_score_id               (stretta_score_id)
#
# Foreign Keys
#
#  score_id          (score_id => scores.id) ON DELETE => cascade
#  stretta_score_id  (stretta_score_id => scores.id) ON DELETE => cascade
#
class ScoreStrettaMatch < ApplicationRecord
  belongs_to :score
  belongs_to :stretta_score, class_name: "Score"

  validates :rank, inclusion: { in: 1..StrettaMatchFinder::MAX_MATCHES }
end
