require 'rails_helper'

RSpec.describe ScoresHelper, type: :helper do
  describe '#format_score_price' do
    let(:score) { build(:score, :smd) }

    it 'formats USD price' do
      expect(helper.format_score_price(score)).to eq("$7.19")
    end

    it 'returns nil when price is blank' do
      score.price_usd = nil
      expect(helper.format_score_price(score)).to be_nil
    end
  end

  describe '#score_on_sale?' do
    it 'returns true when original price exceeds current' do
      score = build(:score, :smd_on_sale)
      expect(helper.score_on_sale?(score)).to be true
    end

    it 'returns false when no original price' do
      score = build(:score, :smd)
      expect(helper.score_on_sale?(score)).to be false
    end
  end

  describe '#format_score_price_with_sale' do
    it 'returns hash with current price only when not on sale' do
      score = build(:score, :smd)
      expect(helper.format_score_price_with_sale(score)).to eq({ current: "$7.19" })
    end

    it 'returns hash with current and original when on sale' do
      score = build(:score, :smd_on_sale)
      result = helper.format_score_price_with_sale(score)
      expect(result[:current]).to eq("$7.19")
      expect(result[:original]).to eq("$8.99")
    end
  end

  describe '#score_page_title' do
    it 'uses a buy-intent form for an SMD score with a category' do
      score = build(:score, :smd, title: 'Crazy Train', smd_category: 'Jazz Ensemble')
      expect(helper.score_page_title(score)).to eq('Crazy Train for Jazz Ensemble — Sheet Music')
    end

    it 'keeps the plain "Title - Composer" form for a free score' do
      score = build(:score, title: 'Locus Iste', composer: 'Bruckner')
      expect(helper.score_page_title(score)).to eq('Locus Iste - Bruckner')
    end

    it 'keeps the plain form for an SMD score without a category' do
      score = build(:score, :smd_klassik, title: 'Air', composer: 'Bach')
      expect(helper.score_page_title(score)).to eq('Air - Bach')
    end
  end

  describe '#buy_cta_label' do
    it 'shows the price when one is known' do
      score = build(:score, :smd)
      expect(helper.buy_cta_label(score)).to eq('Buy on SMD — $7.19')
    end

    it 'falls back to the plain view label when no price is known' do
      score = build(:score, :smd, price_usd: nil)
      expect(helper.buy_cta_label(score)).to eq('View on SMD')
    end
  end

  describe 'a Stretta score' do
    let(:score) { build(:score, :stretta, price_eur: 12.80, title: 'Missa brevis') }

    it 'prices in euro, not converted to dollars' do
      expect(helper.format_score_price(score)).to eq('€12.80')
      expect(helper.score_card_badge(score)).to eq({ type: :commercial, text: '€' })
    end

    it 'writes a euro price the German way on the German locale' do
      I18n.with_locale(:de) { expect(helper.format_score_price(score)).to eq('12,80 €') }
    end

    it 'is a Product with a euro Offer and never accessible-for-free' do
      data = JSON.parse(helper.score_json_ld(score))

      expect(data['@type']).to eq('Product')
      expect(data['offers']).to include('price' => '12.80', 'priceCurrency' => 'EUR')
      expect(data['offers']['seller']['name']).to eq('Stretta Music')
      expect(data).not_to have_key('isAccessibleForFree')
    end

    # Product 6244 is €2.30 with a minimum of 10 — the basket is €23.00. An Offer
    # that disagrees with checkout can devalue structured data site-wide.
    it 'declares the minimum order quantity on the Offer and in the buy box' do
      score.price_eur = 2.30
      score.stretta_metadata = { 'minquantity' => 10 }

      expect(helper.minimum_order(score)).to eq({ quantity: 10, total: '€23.00' })
      expect(JSON.parse(helper.score_json_ld(score)).dig('offers', 'eligibleQuantity', 'minValue')).to eq(10)
    end

    it 'points the buy button at the affiliate redirect' do
      expect(helper.buy_redirect_path(score)).to eq("/go/stretta/#{score.external_id}")
    end
  end

  # Adding a partner to COMMERCIAL_PARTNERS without its copy renders "translation
  # missing" on the buy button — the one place users act on.
  describe 'partner copy' do
    it 'exists in every locale for every commercial source' do
      keys = %w[score.buy_on_%s score.view_on_%s score.%s_hint meta.score_cta_%s about.%s_name]

      I18n.available_locales.each do |locale|
        Score::COMMERCIAL_SOURCES.each do |source|
          keys.each do |template|
            key = format(template, source)
            expect(I18n.exists?(key, locale)).to be(true), "missing #{key} for #{locale}"
          end
        end
      end
    end
  end

  describe '#breadcrumb_json_ld' do
    def crumbs(score)
      JSON.parse(helper.breadcrumb_json_ld(score))
    end

    # find_by_slug is stubbed so the gate logic is tested independent of hub
    # cache/threshold state: a name means the hub exists, nil means it does not.
    it 'emits a valid BreadcrumbList with sequential positions and absolute URLs' do
      allow(HubDataBuilder).to receive(:find_by_slug).and_return('Bruckner')
      score = create(:score, title: 'Locus Iste', composer: 'Bruckner')
      data = crumbs(score)

      expect(data['@context']).to eq('https://schema.org')
      expect(data['@type']).to eq('BreadcrumbList')

      items = data['itemListElement']
      expect(items.map { |i| i['position'] }).to eq([1, 2, 3])
      expect(items).to all(include('@type' => 'ListItem'))
      expect(items).to all(satisfy { |i| i['item'].start_with?('http') })
      expect(items[0]['name']).to eq('Home')
      expect(items[2]['name']).to eq('Locus Iste')
      expect(items[2]['item']).to end_with("/scores/#{score.id}")
    end

    it 'points the parent crumb at the composer hub for a free score' do
      allow(HubDataBuilder).to receive(:find_by_slug).with(:composers, 'bruckner-anton').and_return('Bruckner, Anton')
      score = create(:score, title: 'Locus Iste', composer: 'Bruckner, Anton')
      parent = crumbs(score)['itemListElement'][1]

      expect(parent['name']).to eq('Bruckner, Anton')
      expect(parent['item']).to end_with('/composers/bruckner-anton')
    end

    it 'prefers the artist hub over the composer hub for an SMD score' do
      allow(HubDataBuilder).to receive(:find_by_slug).with(:artists, 'ozzy-osbourne').and_return('Ozzy Osbourne')
      score = create(:score, :smd, title: 'Crazy Train', artist: 'Ozzy Osbourne', composer: 'Osbourne, Ozzy')
      parent = crumbs(score)['itemListElement'][1]

      expect(parent['name']).to eq('Ozzy Osbourne')
      expect(parent['item']).to end_with('/artists/ozzy-osbourne')
    end

    it 'falls back to Home -> score when the hub does not exist (below threshold)' do
      allow(HubDataBuilder).to receive(:find_by_slug).and_return(nil)
      score = create(:score, title: 'Obscure Piece', composer: 'Nobody, Really')
      items = crumbs(score)['itemListElement']

      expect(items.map { |i| i['position'] }).to eq([1, 2])
      expect(items.last['name']).to eq('Obscure Piece')
    end

    it 'emits only Home -> score (no exception) when composer and artist are absent' do
      score = create(:score, title: 'Anon', composer: nil, artist: nil)
      items = crumbs(score)['itemListElement']

      expect(items.map { |i| i['position'] }).to eq([1, 2])
      expect(items[0]['name']).to eq('Home')
      expect(items[1]['name']).to eq('Anon')
    end
  end

  describe '#score_json_ld' do
    def ld(score)
      JSON.parse(helper.score_json_ld(score))
    end

    it 'emits a Product Offer that names SMD as seller, with price, brand, and a fallback description' do
      score = build(:score, :smd, brand: 'Hal Leonard', description: nil)
      data = ld(score)

      expect(data['@type']).to eq('Product')
      expect(data['offers']['seller']['name']).to eq('Sheet Music Direct')
      expect(data['offers']['price']).to eq('7.19')
      expect(data['offers']['priceCurrency']).to eq('USD')
      expect(data['brand']['name']).to eq('Hal Leonard')
      expect(data['description']).to be_present
    end

    it 'never emits review or aggregateRating for a commercial score' do
      score = build(:score, :smd)
      data = ld(score)

      expect(data).not_to have_key('review')
      expect(data).not_to have_key('aggregateRating')
    end

    it 'falls back to the site image when the partner gives no thumbnail' do
      score = build(:score, :stretta)
      data = ld(score)

      expect(data['image']).to eq("#{helper.request.base_url}/og-image.png")
    end

    it 'emits a free MusicComposition with no Offer and accessible-for-free' do
      score = build(:score)
      data = ld(score)

      expect(data['@type']).to eq('MusicComposition')
      expect(data).not_to have_key('offers')
      expect(data['isAccessibleForFree']).to be true
    end
  end

  describe '#score_card_badge' do
    it 'returns nil for non-SMD scores (free scores have no badge)' do
      score = build(:score)
      expect(helper.score_card_badge(score)).to be_nil
    end

    it 'returns commercial badge with $ for SMD scores' do
      score = build(:score, :smd)
      result = helper.score_card_badge(score)
      expect(result[:type]).to eq(:commercial)
      expect(result[:text]).to eq("$")
    end

    it 'returns commercial badge for SMD scores on sale (no special treatment)' do
      score = build(:score, :smd_on_sale)
      result = helper.score_card_badge(score)
      expect(result[:type]).to eq(:commercial)
      expect(result[:text]).to eq("$")
    end

    it 'returns nil for SMD scores with zero price' do
      score = build(:score, :smd, price_usd: 0)
      expect(helper.score_card_badge(score)).to be_nil
    end
  end

  describe '#smd_ensemble_fact' do
    it 'links a category to its ensemble hub once the hub exists' do
      create_list(:score, HubDataBuilder::THRESHOLD, :smd, smd_category: 'Concert Band')
      score = build(:score, :smd, smd_category: 'Concert Band')
      expect(helper.smd_ensemble_fact(score)[:link]).to eq(helper.ensemble_path(slug: 'concert-band'))
    end

    it 'returns nil for a format category that has no hub' do
      score = build(:score, :smd, smd_category: 'Piano Solo')
      expect(helper.smd_ensemble_fact(score)).to be_nil
    end

    it 'drops the arrangement cell it would only restate' do
      create_list(:score, HubDataBuilder::THRESHOLD, :smd, smd_category: 'Concert Band')
      score = build(:score, :smd, smd_category: 'Concert Band', arrangement_category: 'Band')
      expect(helper.smd_arrangement_fact(score)).to be_nil
      expect(helper.smd_arrangement_fact(build(:score, :smd, smd_category: 'Piano Solo',
        arrangement_category: 'Piano'))[:value]).to eq('Piano')
    end
  end

  describe 'hub links on the facts grid' do
    def link_for(score, label)
      helper.unified_score_facts(score).find { |f| f[:label] == I18n.t(label) }&.dig(:link)
    end

    it 'sends a period to its hub, resolving LLM variants to the canonical era' do
      create_list(:score, HubDataBuilder::THRESHOLD, period: 'Modern')
      score = build(:score, period: 'Contemporary')
      expect(link_for(score, 'score.period')).to eq(helper.period_path(slug: 'modern'))
    end

    it 'leaves a period unlinked when no hub covers it, since the filter returns nothing' do
      expect(link_for(build(:score, period: 'Civil War Era'), 'score.period')).to be_nil
    end

    it 'sends a genre to its hub' do
      create_list(:score, HubDataBuilder::THRESHOLD, genre: 'Sonata', genre_status: 'normalized')
      score = build(:score, genre: 'Sonata', genre_status: 'normalized')
      expect(link_for(score, 'score.genre')).to eq(helper.genre_path(slug: 'sonata'))
    end

    it 'keeps the filter for a normalized genre below the hub threshold' do
      score = build(:score, genre: 'Sonata', genre_status: 'normalized')
      expect(link_for(score, 'score.genre')).to eq(helper.scores_path(genre: 'Sonata'))
    end

    it 'leaves an unnormalized genre unlinked — the filter would return nothing' do
      score = build(:score, genre: 'Psalm-tunes', genre_status: 'pending')
      expect(link_for(score, 'score.genre')).to be_nil
    end
  end

  describe 'PAGINATION_PARAMS' do
    it 'covers every filter param the scores list and the hub pages accept' do
      accepted = ScoresController::SEARCH_TRIGGER_PARAMS |
                 HubPagesHelper::COMPOSER_FILTER_PARAMS |
                 HubPagesHelper::GENRE_FILTER_PARAMS |
                 HubPagesHelper::PERIOD_FILTER_PARAMS |
                 HubPagesHelper::INSTRUMENT_FILTER_PARAMS

      expect(accepted - ScoresHelper::PAGINATION_PARAMS).to be_empty
    end
  end
end
