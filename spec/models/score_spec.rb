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

        expect(Score.needing_thumbnail).to eq([needs_work])
      end
    end

    describe '.needing_gallery' do
      it 'finds scores with PDF but no gallery pages' do
        needs_work = create(:score, pdf_path: 'test.pdf')
        create(:score, pdf_path: 'test2.pdf').score_pages.create!(page_number: 1)
        create(:score, pdf_path: nil)
        create(:score, pdf_path: 'N/A')

        expect(Score.needing_gallery).to eq([needs_work])
      end
    end

    describe '.needing_pdf_sync' do
      it 'finds external scores with PDF but no synced file' do
        needs_work = create(:score, source: 'imslp', pdf_path: 'test.pdf')
        already_synced = create(:score, source: 'imslp', pdf_path: 'test2.pdf')
        already_synced.pdf_file.attach(io: StringIO.new('x'), filename: 't.pdf', content_type: 'application/pdf')
        create(:score, source: 'pdmx', pdf_path: 'local.pdf')

        expect(Score.needing_pdf_sync).to eq([needs_work])
      end
    end

    describe '.search' do
      it 'finds accented titles and composers with plain ASCII query' do
        etudes = create(:score, title: 'Études transcendantes', composer: 'Liszt')
        dvorak = create(:score, title: 'Symphony', composer: 'Dvořák')

        expect(Score.search('Etudes')).to include(etudes)
        expect(Score.search('Dvorak')).to include(dvorak)
      end
    end

    describe '.by_pricing' do
      it 'filters free and commercial scores' do
        free = create(:score, source: 'pdmx')
        commercial = create(:score, :smd)

        expect(Score.by_pricing('free')).to include(free)
        expect(Score.by_pricing('free')).not_to include(commercial)
        expect(Score.by_pricing('commercial')).to include(commercial)
        expect(Score.by_pricing('invalid')).to include(free, commercial)
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

  describe '#display_title' do
    it 'returns the title for non-SMD scores' do
      expect(build(:score, title: 'Prelude in C').display_title).to eq('Prelude in C')
    end

    it 'returns nil when title is blank, "NA", or "N/A"' do
      expect(build(:score, title: nil).display_title).to be_nil
      expect(build(:score, title: 'NA').display_title).to be_nil
      expect(build(:score, title: 'n/a').display_title).to be_nil
      expect(build(:score, title: 'N/A').display_title).to be_nil
    end

    it 'falls back to title when SMD clean_title is blank' do
      score = build(:score, source: 'smd', title: 'Sonata K.545', clean_title: nil)
      expect(score.display_title).to eq('Sonata K.545')
    end
  end

  describe '#primary_instrument' do
    it 'returns main_instrument for SMD scores, omitting bare "Other"' do
      expect(build(:score, source: 'smd', main_instrument: 'Guitar').primary_instrument).to eq('Guitar')
      expect(build(:score, source: 'smd', main_instrument: 'Other').primary_instrument).to be_nil
      expect(build(:score, source: 'smd', main_instrument: 'Other Strings').primary_instrument).to eq('Other Strings')
    end

    it 'detects ensembles, choral, voice+accompaniment, and solo instruments' do
      expect(build(:score, instruments: 'orchestra').primary_instrument).to eq('Orchestra')
      expect(build(:score, instruments: 'SATB').primary_instrument).to eq('Choir')
      expect(build(:score, instruments: 'SS').primary_instrument).to eq('Vocal')
      expect(build(:score, instruments: 'voice, piano').primary_instrument).to eq('Voice & Piano')
      expect(build(:score, instruments: 'flute, violin, cello').primary_instrument).to eq('Ensemble')
      expect(build(:score, instruments: 'piano').primary_instrument).to eq('Piano')
    end

    it 'returns nil for unknown or missing data' do
      expect(build(:score, instruments: 'XYZ').primary_instrument).to be_nil
      expect(build(:score, instruments: nil).primary_instrument).to be_nil
    end
  end

  describe '.derive_group_key' do
    it 'strips instrument suffix and part numbers from ensemble titles' do
      expect(Score.derive_group_key('Birds of a Feather (arr. Roger Holmes) - Trombone 2'))
        .to eq('birds of a feather (arr. roger holmes)')
      expect(Score.derive_group_key('Crazy Train (arr. Johnnie Vinson) - Pt.3 - Viola'))
        .to eq('crazy train (arr. johnnie vinson)')
    end

    it 'preserves dashes in titles, returns nil for solo products' do
      expect(Score.derive_group_key("Pirates of the Caribbean - Dead Man's Chest - Piano"))
        .to eq("pirates of the caribbean - dead man's chest")
      expect(Score.derive_group_key('Hallelujah')).to be_nil
    end

    it 'includes product code from thumbnail_url to distinguish editions' do
      title = "(Don't Fear) The Reaper (arr. Paul Murtha) - Trombone 1"

      expect(Score.derive_group_key(title, 'https://img.sheetmusic.direct/catalogue/product/hl-07013386-md.jpg'))
        .to eq("(don't fear) the reaper (arr. paul murtha)|hl-07013386")
      expect(Score.derive_group_key(title, nil))
        .to eq("(don't fear) the reaper (arr. paul murtha)")
    end
  end

  describe '.derive_bundle_group_key' do
    it 'returns group_key for bundle when parts exist' do
      group_key = 'birds of a feather (arr. larry moore)|hl-04493257'
      thumb = 'https://img.sheetmusic.direct/catalogue/product/hl-04493257-md.jpg'
      create(:score, :smd, group_key: group_key, thumbnail_url: thumb)

      expect(Score.derive_bundle_group_key('Birds Of A Feather (arr. Larry Moore)', thumb))
        .to eq(group_key)
    end

    it 'returns nil for bundles without parts or non-bundle titles' do
      thumb = 'https://img.sheetmusic.direct/catalogue/product/hl-99999999-md.jpg'
      expect(Score.derive_bundle_group_key('Some Arrangement (arr. Someone)', thumb)).to be_nil
      expect(Score.derive_bundle_group_key('Simple Title', thumb)).to be_nil
    end
  end

  describe '.extract_product_code' do
    it 'extracts HL product code from SMD thumbnail URL' do
      expect(Score.extract_product_code('https://img.sheetmusic.direct/catalogue/product/hl-07013386-md.jpg')).to eq('hl-07013386')
      expect(Score.extract_product_code(nil)).to be_nil
    end
  end

  describe '.deduplicate_arrangements' do
    it 'shows one card per arrangement, preferring Full Score' do
      group_key = 'test arrangement'
      full_score = create(:score, :smd, clean_title: 'Test - Full Score', group_key: group_key, is_group_representative: true)
      create(:score, :smd, clean_title: 'Test - Trumpet 1', group_key: group_key, is_group_representative: false)
      solo = create(:score, :smd, clean_title: 'Solo Product', group_key: nil)

      result = Score.where(source: 'smd').deduplicate_arrangements
      expect(result).to include(full_score, solo)
      expect(result.count).to eq(2)
    end
  end
end
