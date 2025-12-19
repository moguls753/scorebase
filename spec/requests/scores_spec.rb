require 'rails_helper'

RSpec.describe 'Scores' do
  describe 'GET /scores' do
    it 'returns success' do
      get scores_path
      expect(response).to have_http_status(:success)
    end

    it 'displays scores' do
      create(:score, title: 'Test Score')
      get scores_path
      expect(response.body).to include('Test Score')
    end
  end

  describe 'GET /scores/:id' do
    it 'returns success for existing score' do
      score = create(:score)
      get score_path(id: score.id)
      expect(response).to have_http_status(:success)
    end
  end
end
