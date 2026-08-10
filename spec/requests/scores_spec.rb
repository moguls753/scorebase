require 'rails_helper'

RSpec.describe 'Scores' do
  # Two-view homepage (docs/homepage-two-view-spec.md §8): a bare request renders
  # the indexable LANDING (hero + browse doors, no score grid); a request carrying
  # a query or any filter/source/key/time trigger renders the noindex RESULTS view
  # (grid + sticky bar inside turbo-frame#scores).
  describe 'GET /scores (two-view homepage)' do
    def parsed(body)
      Nokogiri::HTML(body)
    end

    context 'landing (no query, no search trigger)' do
      it 'renders the hero, all six browse doors and the Smart Search teaser, with no results frame' do
        get root_path

        expect(response).to have_http_status(:success)
        expect(response.body).to include(I18n.t('search.hero_title_line1'))
        %w[composers artists instruments genres periods ensembles].each do |door|
          expect(response.body).to include(ERB::Util.html_escape(I18n.t("search.browse_#{door}")))
        end
        expect(response.body).to include(composers_path, periods_path, ensembles_path)
        expect(response.body).to include(I18n.t('smart_search_teaser.name'))
        expect(response.body).not_to include('<turbo-frame id="scores"')
      end

      it 'never leaks a score-card grid onto the landing (copyright / no popularity cards)' do
        leak = create(:score, title: 'Grid Leak Sonata')

        get root_path

        expect(response.body).not_to include("/scores/#{leak.id}")
        expect(response.body).not_to include('Grid Leak Sonata')
      end

      it 'stays indexable (emits no robots meta)' do
        get root_path

        expect(response.body).not_to include('name="robots"')
      end

      it 'pairs the homepage with /de, not /de/, so the hreflang cluster is reciprocal' do
        get root_path

        expect(response.body).to include('hreflang="de" href="http://www.example.com/de"')
      end

      it 'renders the landing for a bare /scores too' do
        get scores_path

        expect(response.body).to include(I18n.t('search.or_explore'))
        expect(response.body).not_to include('<turbo-frame id="scores"')
      end
    end

    context 'results (query, filter, or source/key/time trigger)' do
      it 'renders the grid inside turbo-frame#scores and echoes the query into the compact bar' do
        score = create(:score, title: 'Ave Verum')

        get scores_path(q: 'Ave')

        expect(response).to have_http_status(:success)
        expect(response.body).to include('Ave Verum', "/scores/#{score.id}", '<turbo-frame id="scores"')
        query_field = parsed(response.body).at_css('input[type="search"][name="q"]')
        expect(query_field['value']).to eq('Ave')
      end

      it 'is noindex,follow and sheds the landing chrome' do
        get scores_path(q: 'somequerywithnohits')

        expect(response.body).to include('noindex,follow')
        expect(response.body).not_to include(I18n.t('search.or_explore'))
      end

      it 'emits no canonical or hreflang alongside noindex' do
        get scores_path(instrument: 'piano')

        expect(response.body).to include('noindex,follow')
        expect(response.body).not_to include('rel="canonical"')
        expect(response.body).not_to include('rel="alternate" hreflang')
      end

      it 'filters by voicing and rejects invalid voicing params' do
        create(:score, title: 'Solo Piece', num_parts: 1)
        create(:score, title: 'Quartet Piece', num_parts: 4)

        get scores_path(voicing: 'solo')
        expect(response.body).to include('Solo Piece')
        expect(response.body).not_to include('Quartet Piece')

        get scores_path(voicing: 'invalid_garbage_123')
        expect(response.body).not_to include('Solo Piece')
      end

      it 'renders results for a filter-only deep link' do
        create(:score, title: 'Piano Prelude', instruments: 'Piano')

        get scores_path(instrument: 'piano')

        expect(response.body).to include('<turbo-frame id="scores"')
        expect(response.body).not_to include(I18n.t('search.or_explore'))
      end

      it 'treats source as a trigger and filters by it' do
        create(:score, :cpdl, title: 'Cpdl Motet')
        create(:score, :pdmx, title: 'Pdmx Sonata')

        get scores_path(source: 'cpdl')

        expect(response.body).to include('Cpdl Motet')
        expect(response.body).not_to include('Pdmx Sonata')
        expect(response.body).not_to include(I18n.t('search.or_explore'))
      end

      it 'treats key and time signature as search triggers (results, not landing)' do
        get scores_path(key: 'G')
        expect(response.body).to include('<turbo-frame id="scores"')
        expect(response.body).not_to include(I18n.t('search.or_explore'))

        get scores_path(time: '4/4')
        expect(response.body).to include('<turbo-frame id="scores"')
        expect(response.body).not_to include(I18n.t('search.or_explore'))
      end

      it 'carries the source trigger into a sort refinement via a hidden field' do
        get scores_path(source: 'cpdl', sort: 'newest')

        sort_forms = parsed(response.body).css('form').select { |f| f.at_css('select[name="sort"]') }
        expect(sort_forms).to be_present
        carried = sort_forms.any? do |f|
          hidden = f.at_css('input[type="hidden"][name="source"]')
          hidden && hidden['value'] == 'cpdl'
        end
        expect(carried).to be(true)
      end

      it 'sorts without dropping matches' do
        create(:score, title: 'Piece One')
        create(:score, title: 'Piece Two')

        get scores_path(q: 'piece', sort: 'newest')

        expect(response).to have_http_status(:success)
        expect(response.body).to include('Piece One', 'Piece Two')
      end

      it 'returns 404 for out-of-range pagination inside the results branch' do
        25.times { |i| create(:score, title: "Piece #{i}") }

        get scores_path(q: 'Piece', page: 9999)

        expect(response).to have_http_status(:not_found)
      end

      it 'returns the landing (200) for a bare out-of-range page — the 404 is scoped to results' do
        get scores_path(page: 9999)

        expect(response).to have_http_status(:success)
        expect(response.body).to include(I18n.t('search.or_explore'))
      end

      it 'renders the zero-results empty state (200, not 404, not a blank grid)' do
        create(:score, title: 'Something Else')

        get scores_path(q: 'zzzznomatch')

        expect(response).to have_http_status(:success)
        expect(response.body).to include(
          I18n.t('hub.no_scores_found'),
          I18n.t('smart_search_teaser.name'),
          'id="scores-results-heading"'
        )
        expect(response.body).not_to match(%r{/scores/\d})
      end

      it 'keeps the filter in the prev link — dropping it would flip page 2 back to the landing view' do
        25.times { |i| create(:score, title: "Piano Piece #{i}", instruments: 'Piano') }

        get scores_path(instrument: 'piano', page: 2)

        prev_href = parsed(response.body).at_css('a[rel="prev"]')&.[]('href')
        expect(prev_href).to eq('/scores?instrument=piano')
      end

      it 'points the Clear link at the bare landing URL when only filters survive (frame-missing net, server half)' do
        create(:score, title: 'Piano Prelude', instruments: 'Piano')

        get scores_path(instrument: 'piano')

        expect(response.body).to include('href="/scores"')
      end
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

      it 'never noindexes a show page over a stray ?page, keeping the representative canonical' do
        get score_path(id: member.id, page: 2)

        expect(response.body).not_to include('name="robots"')
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

    describe 'Phase 2a CTR lifts (buy-intent title, priced CTA, breadcrumbs)' do
      def breadcrumb_json_ld(body)
        script = body.scan(%r{<script type="application/ld\+json">\s*(.+?)\s*</script>}m)
                     .map { |m| JSON.parse(m[0]) }
                     .find { |d| d['@type'] == 'BreadcrumbList' }
        script
      end

      it 'gives an SMD category score a buy-intent title, priced CTA, and a breadcrumb' do
        smd = create(:score, :smd, title: 'Crazy Train', smd_category: 'Jazz Ensemble', price_usd: 64.79)

        get score_path(id: smd.id)

        expect(response.body).to include('<title>Crazy Train for Jazz Ensemble — Sheet Music | ScoreBase</title>')
        expect(response.body).to include('Buy on SMD — $64.79')

        crumbs = breadcrumb_json_ld(response.body)
        expect(crumbs).to be_present
        # Positions sequential (hub crumb present only if the hub meets threshold,
        # which it won't in a fresh test DB — so 2 or 3 items, always ending at the score)
        positions = crumbs['itemListElement'].map { |i| i['position'] }
        expect(positions).to eq((1..positions.size).to_a)
        expect(crumbs['itemListElement'].last['name']).to eq('Crazy Train')
      end

      it 'wires the SMD buy button to the client-side click-tracking hook' do
        smd = create(:score, :smd, title: 'Crazy Train', price_usd: 64.79)

        get score_path(id: smd.id)

        expect(response.body).to include(%(data-smd-redirect-score-id-value="#{smd.id}"))
      end

      it 'includes the SMD category in the meta description' do
        smd = create(:score, :smd, title: 'Fanfare', smd_category: 'Concert Band', instruments: 'Trumpet')

        get score_path(id: smd.id)

        expect(response.body).to match(/<meta name="description"[^>]*Concert Band/)
      end

      it 'leaves a free score title plain and its buy area unchanged' do
        free = create(:score, :pdmx, title: 'Test Piece', composer: 'Test Composer')

        get score_path(id: free.id)

        expect(response.body).to include('<title>Test Piece - Test Composer | ScoreBase</title>')
        expect(response.body).to include('Download PDF') # the free download button really renders
        expect(response.body).not_to include('Buy on SMD')
        expect(response.body).not_to include('View on SMD')
      end

      it 'appends the catalog number to the title, h1 and meta description of an IMSLP score' do
        score = create(:score, :imslp, title: 'Magnificat Fugue', composer: 'Pachelbel', catalog_number: 'P.257')

        get score_path(id: score.id)

        expect(response.body).to include('<title>Magnificat Fugue, P.257 - Pachelbel | ScoreBase</title>')
        expect(response.body).to include('Magnificat Fugue, P.257</h1>')
        expect(response.body).to match(/<meta name="description"[^>]*Magnificat Fugue, P\.257 by Pachelbel/)
      end

      it 'renders the German priced CTA on the /de SMD page' do
        smd = create(:score, :smd, title: 'Crazy Train', price_usd: 64.79)

        get score_path(id: smd.id, locale: 'de')

        expect(response.body).to include('Bei SMD kaufen — $64.79')
      end
    end

    describe 'professional editions cross-links' do
      let(:browser_headers) do
        { 'HTTP_USER_AGENT' => 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36' }
      end
      let(:free) { create(:score, title: 'Locus Iste', composer: 'Bruckner, Anton') }
      let(:edition) { create(:score, :smd, title: 'Locus Iste', composer: 'Anton Bruckner') }

      it 'renders the section linking to the matched edition' do
        ScoreSmdMatch.create!(score: free, smd_score: edition, rank: 1)

        get score_path(id: free.id)

        expect(response.body).to include('Professional Editions')
        expect(response.body).to include(score_path(id: edition.id))
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

      it 'never creates an Ahoy visit server-side' do
        expect {
          get score_path(id: edition.id), headers: browser_headers
        }.not_to change { Ahoy::Visit.count }
      end

      it 'skips the view counter on Turbo hover-prefetch requests' do
        expect {
          get score_path(id: edition.id),
              headers: browser_headers.merge('HTTP_X_SEC_PURPOSE' => 'prefetch')
        }.not_to change { edition.reload.views }
      end
    end

    describe 'gallery preview image' do
      it 'renders the stored thumbnail attachment when thumbnail_url is absent (CPDL/OpenScore)' do
        # Real attachment so has_thumbnail? is genuinely true; stub only the URL (Disk service
        # can't generate one in test). object-contain is unique to the gallery image branch.
        allow_any_instance_of(Score).to receive(:thumbnail).and_return('https://cdn.test/preview.webp')
        score = create(:score, :cpdl, thumbnail_url: nil)
        score.thumbnail_image.attach(io: StringIO.new('x'), filename: 't.webp', content_type: 'image/webp')

        get score_path(id: score.id)

        expect(response).to have_http_status(:success)
        expect(response.body).to include('object-contain')
      end
    end

    describe 'language switcher' do
      it 'links to the unprefixed English URL on a German page, not a /en/ redirect' do
        score = create(:score, title: 'Test Piece')

        get score_path(id: score.id, locale: 'de')

        expect(response).to have_http_status(:success)
        expect(response.body).not_to include("/en/scores/#{score.id}")
      end
    end
  end
end
