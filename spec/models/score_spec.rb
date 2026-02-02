require 'rails_helper'

RSpec.describe Score do
  describe 'validations' do
    it { should validate_presence_of(:title) }
    it { should validate_uniqueness_of(:data_path).allow_nil }
    it { should validate_uniqueness_of(:external_id).scoped_to(:source).allow_nil }
    it { should validate_inclusion_of(:source).in_array(Score::SOURCES).allow_nil }
  end

  describe 'scopes' do
    describe '.needing_thumbnail' do
      it 'finds scores with URL but no cached thumbnail' do
        needs_work = create(:score, thumbnail_url: 'https://example.com/thumb.png')
        already_cached = create(:score, thumbnail_url: 'https://example.com/thumb2.png')
        already_cached.thumbnail_image.attach(io: StringIO.new('x'), filename: 't.webp', content_type: 'image/webp')
        no_url = create(:score, thumbnail_url: nil)

        expect(Score.needing_thumbnail).to eq([needs_work])
      end
    end

    describe '.needing_gallery' do
      it 'finds scores with PDF but no gallery pages' do
        needs_work = create(:score, pdf_path: 'test.pdf')
        already_done = create(:score, pdf_path: 'test2.pdf')
        already_done.score_pages.create!(page_number: 1)
        no_pdf = create(:score, pdf_path: nil)
        na_pdf = create(:score, pdf_path: 'N/A')

        expect(Score.needing_gallery).to eq([needs_work])
      end
    end

    describe '.needing_pdf_sync' do
      it 'finds external scores with PDF but no synced file' do
        needs_work = create(:score, source: 'imslp', pdf_path: 'test.pdf')
        already_synced = create(:score, source: 'imslp', pdf_path: 'test2.pdf')
        already_synced.pdf_file.attach(io: StringIO.new('x'), filename: 't.pdf', content_type: 'application/pdf')
        pdmx_score = create(:score, source: 'pdmx', pdf_path: 'local.pdf')
        no_pdf = create(:score, source: 'cpdl', pdf_path: nil)

        expect(Score.needing_pdf_sync).to eq([needs_work])
      end
    end

    describe '.search' do
      it 'finds accented titles with plain ASCII query' do
        score = create(:score, title: 'Études transcendantes', composer: 'Liszt')
        create(:score, title: 'Sonata', composer: 'Mozart')

        expect(Score.search('Etudes')).to include(score)
        expect(Score.search('Études')).to include(score)
      end

      it 'finds accented composers with plain ASCII query' do
        score = create(:score, title: 'Symphony', composer: 'Dvořák')

        expect(Score.search('Dvorak')).to include(score)
      end
    end

    describe '.by_pricing' do
      it 'filters free scores (non-SMD or SMD without price)' do
        free_pdmx = create(:score, source: 'pdmx')
        free_cpdl = create(:score, source: 'cpdl')
        smd_with_price = create(:score, :smd)
        smd_no_price = create(:score, source: 'smd', price_usd: nil)

        result = Score.by_pricing('free')
        expect(result).to include(free_pdmx, free_cpdl, smd_no_price)
        expect(result).not_to include(smd_with_price)
      end

      it 'filters commercial scores (SMD with price)' do
        free_pdmx = create(:score, source: 'pdmx')
        smd_with_price = create(:score, :smd)
        smd_no_price = create(:score, source: 'smd', price_usd: nil)

        result = Score.by_pricing('commercial')
        expect(result).to include(smd_with_price)
        expect(result).not_to include(free_pdmx, smd_no_price)
      end

      it 'returns all scores for invalid pricing param' do
        free_pdmx = create(:score, source: 'pdmx')
        smd_with_price = create(:score, :smd)

        expect(Score.by_pricing('invalid')).to include(free_pdmx, smd_with_price)
        expect(Score.by_pricing('')).to include(free_pdmx, smd_with_price)
      end
    end
  end

  describe '#thumbnail' do
    it 'prefers cached over external URL' do
      score = create(:score, thumbnail_url: 'https://example.com/thumb.png')
      expect(score.thumbnail).to eq('https://example.com/thumb.png')

      score.thumbnail_image.attach(io: StringIO.new('x'), filename: 't.webp', content_type: 'image/webp')
      allow(score.thumbnail_image).to receive(:url).and_return('http://r2/cached.webp')
      expect(score.thumbnail).to eq('http://r2/cached.webp')
    end
  end

  describe '#smd_purchasable?' do
    it 'requires SMD source and external_id' do
      expect(build(:score, :smd).smd_purchasable?).to be true
      expect(build(:score, source: 'smd', external_id: nil).smd_purchasable?).to be false
      expect(build(:score, :pdmx).smd_purchasable?).to be false
    end
  end

  describe '#primary_instrument' do
    it 'returns main_instrument for SMD scores' do
      score = build(:score, source: 'smd', main_instrument: 'Guitar')
      expect(score.primary_instrument).to eq('Guitar')
    end

    it 'detects ensemble keywords' do
      expect(build(:score, instruments: 'orchestra').primary_instrument).to eq('Orchestra')
      expect(build(:score, instruments: 'concert band').primary_instrument).to eq('Band')
    end

    it 'maps choral codes to Choir (3+ voices) or Vocal (2 voices)' do
      expect(build(:score, instruments: 'SATB').primary_instrument).to eq('Choir')
      expect(build(:score, instruments: 'SSA, Piano').primary_instrument).to eq('Choir')
      expect(build(:score, instruments: 'SS').primary_instrument).to eq('Vocal')
      expect(build(:score, instruments: 'TB').primary_instrument).to eq('Vocal')
    end

    it 'preserves A cappella' do
      expect(build(:score, instruments: 'A cappella').primary_instrument).to eq('A cappella')
    end

    it 'formats voice + accompaniment' do
      expect(build(:score, instruments: 'voice, piano').primary_instrument).to eq('Voice & Piano')
      expect(build(:score, instruments: 'soprano, organ').primary_instrument).to eq('Voice & Organ')
      expect(build(:score, instruments: 'tenor, guitar').primary_instrument).to eq('Voice & Guitar')
    end

    it 'returns Ensemble for 3+ instruments' do
      expect(build(:score, instruments: 'flute, violin, cello').primary_instrument).to eq('Ensemble')
    end

    it 'returns known instruments capitalized' do
      expect(build(:score, instruments: 'piano').primary_instrument).to eq('Piano')
      expect(build(:score, instruments: 'violin').primary_instrument).to eq('Violin')
      expect(build(:score, instruments: 'flute').primary_instrument).to eq('Flute')
    end

    it 'returns nil for unknown patterns' do
      expect(build(:score, instruments: 'Unknown').primary_instrument).to be_nil
      expect(build(:score, instruments: 'XYZ').primary_instrument).to be_nil
    end

    it 'returns nil when no instrument data' do
      expect(build(:score, instruments: nil).primary_instrument).to be_nil
      expect(build(:score, instruments: '').primary_instrument).to be_nil
    end
  end

  describe '.derive_group_key' do
    it 'extracts group key from ensemble part titles' do
      expect(Score.derive_group_key('Birds of a Feather (arr. Roger Holmes) - Trombone 2'))
        .to eq('birds of a feather (arr. roger holmes)')
    end

    it 'strips Pt.X segments for flex-band arrangements' do
      expect(Score.derive_group_key('Crazy Train (arr. Johnnie Vinson) - Pt.3 - Viola'))
        .to eq('crazy train (arr. johnnie vinson)')
      expect(Score.derive_group_key('Crazy Train (arr. Johnnie Vinson) - Pt. 5 - Cello/Bass'))
        .to eq('crazy train (arr. johnnie vinson)')
    end

    it 'strips Sample Solo segments' do
      expect(Score.derive_group_key('Sesame Street Theme (arr. Mike Tomaro) - Sample Solo - Trumpet'))
        .to eq('sesame street theme (arr. mike tomaro)')
    end

    it 'preserves dashes in movie/album titles' do
      expect(Score.derive_group_key("Pirates of the Caribbean - Dead Man's Chest - Piano"))
        .to eq("pirates of the caribbean - dead man's chest")
    end

    it 'returns nil for solo products without instrument suffix' do
      expect(Score.derive_group_key('Hallelujah')).to be_nil
      expect(Score.derive_group_key('Star Wars - Main Theme')).to be_nil
    end

    it 'includes product code from thumbnail_url to distinguish editions' do
      title = "(Don't Fear) The Reaper (arr. Paul Murtha) - Trombone 1"
      jazz_thumb = 'https://img.sheetmusic.direct/catalogue/product/hl-07013386-md.jpg'
      concert_thumb = 'https://img.sheetmusic.direct/catalogue/product/hl-04005714-md.jpg'

      expect(Score.derive_group_key(title, jazz_thumb))
        .to eq("(don't fear) the reaper (arr. paul murtha)|hl-07013386")
      expect(Score.derive_group_key(title, concert_thumb))
        .to eq("(don't fear) the reaper (arr. paul murtha)|hl-04005714")
    end

    it 'works without thumbnail_url for backwards compatibility' do
      expect(Score.derive_group_key('Test - Trumpet 1'))
        .to eq('test')
      expect(Score.derive_group_key('Test - Trumpet 1', nil))
        .to eq('test')
    end
  end

  describe '.derive_bundle_group_key' do
    it 'returns group_key for bundle when parts exist' do
      thumb = 'https://img.sheetmusic.direct/catalogue/product/hl-04493257-md.jpg'
      group_key = 'birds of a feather (arr. larry moore)|hl-04493257'

      # Create a part with this group_key
      create(:score, :smd, group_key: group_key, thumbnail_url: thumb)

      # Bundle should now get the same group_key
      expect(Score.derive_bundle_group_key('Birds Of A Feather (arr. Larry Moore)', thumb))
        .to eq(group_key)
    end

    it 'returns nil for bundle without existing parts' do
      thumb = 'https://img.sheetmusic.direct/catalogue/product/hl-99999999-md.jpg'
      expect(Score.derive_bundle_group_key('Some Arrangement (arr. Someone)', thumb)).to be_nil
    end

    it 'returns nil for non-bundle titles' do
      thumb = 'https://img.sheetmusic.direct/catalogue/product/hl-04493257-md.jpg'
      # Has instrument suffix - not a bundle
      expect(Score.derive_bundle_group_key('Title - Trumpet 1', thumb)).to be_nil
      # No arranger attribution
      expect(Score.derive_bundle_group_key('Simple Title', thumb)).to be_nil
    end
  end

  describe '.extract_product_code' do
    it 'extracts HL product code from SMD thumbnail URL' do
      url = 'https://img.sheetmusic.direct/catalogue/product/hl-07013386-md.jpg'
      expect(Score.extract_product_code(url)).to eq('hl-07013386')
    end

    it 'returns nil for non-SMD URLs' do
      expect(Score.extract_product_code('https://example.com/image.jpg')).to be_nil
      expect(Score.extract_product_code(nil)).to be_nil
      expect(Score.extract_product_code('')).to be_nil
    end
  end

  describe '.deduplicate_arrangements' do
    it 'shows one card per arrangement, preferring Full Score' do
      group_key = 'test arrangement'
      full_score = create(:score, :smd, clean_title: 'Test - Full Score', group_key: group_key, is_group_representative: true)
      create(:score, :smd, clean_title: 'Test - Trumpet 1', group_key: group_key, is_group_representative: false)
      create(:score, :smd, clean_title: 'Test - Trombone 1', group_key: group_key, is_group_representative: false)
      solo = create(:score, :smd, clean_title: 'Solo Product', group_key: nil)

      result = Score.where(source: 'smd').deduplicate_arrangements
      expect(result).to include(full_score, solo)
      expect(result.count).to eq(2)
    end
  end
end
