require 'rails_helper'

RSpec.describe 'Scores' do
  describe 'GET /scores' do
    it 'returns success and displays scores' do
      create(:score, title: 'Test Score')
      get scores_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Test Score')
    end

    it 'filters by voicing' do
      create(:score, title: 'Solo Piece', num_parts: 1)
      create(:score, title: 'SATB Piece', voicing: 'SATB')
      create(:score, title: 'Quartet Piece', num_parts: 4)

      get scores_path(voicing: 'solo')
      expect(response.body).to include('Solo Piece')
      expect(response.body).not_to include('Quartet Piece')

      get scores_path(voicing: 'satb')
      expect(response.body).to include('SATB Piece')
    end

    it 'rejects invalid voicing params' do
      create(:score, title: 'Some Piece')

      get scores_path(voicing: 'invalid_garbage_123')
      expect(response.body).not_to include('Some Piece')
    end
  end

  describe 'GET /scores/:id' do
    it 'returns success with valid JSON-LD structured data' do
      score = create(:score, title: 'Test Piece', composer: 'Test Composer')
      get score_path(id: score.id)
      expect(response).to have_http_status(:success)

      json_ld_match = response.body.match(/<script type="application\/ld\+json">\s*(.+?)\s*<\/script>/m)
      json_ld = JSON.parse(json_ld_match[1])

      expect(json_ld['@type']).to eq('MusicComposition')
      expect(json_ld['name']).to eq('Test Piece')
      expect(json_ld['composer']['name']).to eq('Test Composer')
    end

    it 'includes SEO-critical metadata in JSON-LD' do
      score = create(:score,
        title: 'Sonata in C Major', composer: 'J.S. Bach',
        duration_seconds: 180, page_count: 8, period: 'Baroque',
        genre: 'Sacred music-Choral music', voicing: 'SATB', instruments: 'A cappella'
      )
      get score_path(id: score.id)

      json_ld_match = response.body.match(/<script type="application\/ld\+json">\s*(.+?)\s*<\/script>/m)
      json_ld = JSON.parse(json_ld_match[1])

      expect(json_ld['timeRequired']).to eq('PT3M')
      expect(json_ld['numberOfPages']).to eq(8)
      expect(json_ld['genre']).to include('Sacred music', 'Baroque')
    end
  end
end
