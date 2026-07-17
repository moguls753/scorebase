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

    it 'returns 404 for out-of-range pagination' do
      create(:score, title: 'Only Piece')

      get scores_path(page: 9999)
      expect(response).to have_http_status(:not_found)
    end

    it 'emits noindex,follow on paginated pages (?page>=2)' do
      30.times { |i| create(:score, title: "Piece #{i}") }

      get scores_path(page: 2)
      expect(response.body).to include('<meta name="robots" content="noindex,follow">')
    end

    it 'does not emit a robots meta tag on page 1' do
      create(:score, title: 'Piece')

      get scores_path
      expect(response.body).not_to include('<meta name="robots"')
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

    it 'returns 410 Gone for soft-deleted scores' do
      score = create(:score, title: 'Dead Piece', deleted_at: Time.current)

      get score_path(id: score.id)
      expect(response).to have_http_status(:gone)
    end

    it 'returns 404 for non-existent scores' do
      get score_path(id: 999_999_999)
      expect(response).to have_http_status(:not_found)
    end

    describe 'canonical link (near-dupe consolidation)' do
      def canonical_href(body)
        body[%r{<link rel="canonical" href="([^"]+)">}, 1]
      end

      let(:group_key) { 'crazy train|hl-123' }
      let!(:rep) do
        create(:score, :smd, title: 'Crazy Train - Full Score', group_key: group_key, is_group_representative: true)
      end
      let!(:member) do
        create(:score, :smd, title: 'Crazy Train - Trombone 2', group_key: group_key, is_group_representative: false)
      end

      it 'points a hidden member at the representative url (en), not at itself' do
        get score_path(id: member.id)

        href = canonical_href(response.body)
        expect(href).to end_with("/scores/#{rep.id}")
        expect(href).not_to include("/scores/#{member.id}")
      end

      it 'points a hidden member at the representative url in the same locale (de)' do
        get score_path(id: member.id, locale: 'de')

        href = canonical_href(response.body)
        expect(href).to end_with("/de/scores/#{rep.id}")
        expect(href).not_to include("/scores/#{member.id}")
      end

      it 'leaves the representative self-canonical' do
        get score_path(id: rep.id)

        expect(canonical_href(response.body)).to end_with("/scores/#{rep.id}")
      end

      it 'leaves a free score self-canonical' do
        free = create(:score, title: 'Locus Iste')

        get score_path(id: free.id)

        expect(canonical_href(response.body)).to end_with("/scores/#{free.id}")
      end

      it 'leaves an SMD ungrouped score self-canonical' do
        ungrouped = create(:score, :smd, title: 'Solo Product', group_key: nil)

        get score_path(id: ungrouped.id)

        expect(canonical_href(response.body)).to end_with("/scores/#{ungrouped.id}")
      end

      it 'suppresses self-hreflang on a canonicalized-away member but keeps it on the representative' do
        get score_path(id: member.id)
        expect(response.body).not_to include('hreflang')

        get score_path(id: rep.id)
        expect(response.body).to include('hreflang="en"')
      end
    end

    describe 'JSON-LD by pricing (Product vs MusicComposition)' do
      def json_ld(body)
        m = body.match(%r{<script type="application/ld\+json">\s*(.+?)\s*</script>}m)
        JSON.parse(m[1])
      end

      it 'emits Product + Offer with the price for a commercial SMD score' do
        smd = create(:score, :smd, title: 'Crazy Train', price_usd: 79.49)

        get score_path(id: smd.id)
        data = json_ld(response.body)

        expect(data['@type']).to eq('Product')
        expect(data['offers']).to include('price' => '79.49', 'priceCurrency' => 'USD')
        expect(data['offers']['availability']).to eq('https://schema.org/InStock')
        expect(data).not_to have_key('isAccessibleForFree')
        expect(data).not_to have_key('review')
        expect(data).not_to have_key('aggregateRating')
      end

      it 'keeps a free score as an accessible MusicComposition' do
        free = create(:score, title: 'Locus Iste', composer: 'Bruckner')

        get score_path(id: free.id)
        data = json_ld(response.body)

        expect(data['@type']).to eq('MusicComposition')
        expect(data['isAccessibleForFree']).to be true
      end

      it 'falls back to MusicComposition for a priceless SMD score' do
        smd = create(:score, :smd, title: 'No Price', price_usd: 0)

        get score_path(id: smd.id)

        expect(json_ld(response.body)['@type']).to eq('MusicComposition')
      end
    end

    describe 'professional editions cross-links' do
      let(:browser_headers) do
        { 'HTTP_USER_AGENT' => 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36' }
      end
      let(:free) { create(:score, title: 'Locus Iste', composer: 'Bruckner, Anton') }
      let(:edition) { create(:score, :smd, title: 'Locus Iste', composer: 'Anton Bruckner') }

      it 'renders the section with an xlink-tagged link when a match exists' do
        ScoreSmdMatch.create!(score: free, smd_score: edition, rank: 1)

        get score_path(id: free.id)

        expect(response.body).to include('Professional Editions')
        expect(response.body).to include(score_path(id: edition.id, src: 'xlink'))
      end

      it 'omits the section without matches' do
        get score_path(id: free.id)

        expect(response.body).not_to include('Professional Editions')
      end

      it 'omits the section on SMD score pages even when match rows point at them' do
        other = create(:score, :smd, title: 'Locus Iste - Full Score')
        ScoreSmdMatch.create!(score: edition, smd_score: other, rank: 1)

        get score_path(id: edition.id)

        expect(response.body).not_to include('Professional Editions')
      end

      it 'tracks an xlink visit for real browsers only' do
        expect {
          get score_path(id: edition.id, src: 'xlink'), headers: browser_headers
        }.to change { Ahoy::Event.where(name: 'Cross-link visit').count }.by(1)
        expect(Ahoy::Event.last.properties).to eq('score_id' => edition.id)

        expect {
          get score_path(id: edition.id, src: 'xlink')
        }.not_to change { Ahoy::Event.count }
      end

      it 'never tracks without the xlink param or on non-SMD targets' do
        expect {
          get score_path(id: edition.id), headers: browser_headers
          get score_path(id: free.id, src: 'xlink'), headers: browser_headers
        }.not_to change { Ahoy::Event.where(name: 'Cross-link visit').count }
      end

      it 'ignores Turbo hover-prefetch requests' do
        expect {
          get score_path(id: edition.id, src: 'xlink'),
              headers: browser_headers.merge('HTTP_X_SEC_PURPOSE' => 'prefetch')
        }.not_to change { Ahoy::Event.count }
      end
    end
  end
end
