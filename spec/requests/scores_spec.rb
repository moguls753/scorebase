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

    it 'includes valid JSON-LD structured data' do
      score = create(:score, title: 'Test Piece', composer: 'Test Composer')
      get score_path(id: score.id)

      # Extract JSON-LD from response
      expect(response.body).to include('application/ld+json')
      json_ld_match = response.body.match(/<script type="application\/ld\+json">\s*(.+?)\s*<\/script>/m)
      expect(json_ld_match).not_to be_nil

      # Parse JSON-LD to verify it's valid JSON
      json_ld = JSON.parse(json_ld_match[1])

      # Verify required fields
      expect(json_ld['@context']).to eq('https://schema.org')
      expect(json_ld['@type']).to eq('MusicComposition')
      expect(json_ld['name']).to eq('Test Piece')
      expect(json_ld['composer']['name']).to eq('Test Composer')
      expect(json_ld['isAccessibleForFree']).to be true
    end

    it 'includes SEO-critical metadata in JSON-LD' do
      score = create(
        :score,
        title: 'Sonata in C Major',
        composer: 'J.S. Bach',
        duration_seconds: 180,
        page_count: 8,
        license: 'Public Domain',
        posted_date: Date.parse('2024-01-01'),
        voicing: 'SATB',
        instruments: 'A cappella',
        period: 'Baroque',
        genre: 'Sacred music-Choral music'
      )
      get score_path(id: score.id)

      json_ld_match = response.body.match(/<script type="application\/ld\+json">\s*(.+?)\s*<\/script>/m)
      json_ld = JSON.parse(json_ld_match[1])

      # SEO-critical fields for music catalogs
      expect(json_ld['timeRequired']).to eq('PT3M') # ISO 8601 duration
      expect(json_ld['numberOfPages']).to eq(8)
      expect(json_ld['license']).to eq('Public Domain')
      expect(json_ld['datePublished']).to eq('2024-01-01')

      # Critical for music discovery
      expect(json_ld['musicArrangement']).to eq('SATB, A cappella')
      expect(json_ld['genre']).to include('Sacred music', 'Choral music', 'Baroque')
    end
  end
end
