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

      it 'counts a priceless commercial score as free' do
        priceless = create(:score, :smd, price_usd: nil)

        expect(Score.by_pricing('free')).to include(priceless)
        expect(Score.by_pricing('commercial')).not_to include(priceless)
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

  # group_rank leads GROUP_REPRESENTATIVE_ORDER_SQL. SMD never sets it, so its
  # representative must still be picked by title shape and price.
  describe 'group_rank in the representative order' do
    it 'leaves an SMD group ranked by title shape' do
      set = create(:score, :smd, title: 'Crazy Train (arr. Holmes)', group_key: 'g', price_usd: 5)
      part = create(:score, :smd, title: 'Crazy Train (arr. Holmes) - Trombone 2', group_key: 'g', price_usd: 90)

      BackfillGroupKeysJob.new.send(:assign_representatives)

      expect(set.reload.is_group_representative).to be true
      expect(part.reload.is_group_representative).to be_nil
    end

    it 'lets group_rank decide when it is set' do
      score = create(:score, source: 'stretta', external_id: '1', title: 'Missa', group_key: 'g', group_rank: 10)
      part = create(:score, source: 'stretta', external_id: '2', title: 'Missa', group_key: 'g', group_rank: 70)

      BackfillGroupKeysJob.new.send(:assign_representatives)

      expect(score.reload.is_group_representative).to be true
      expect(part.reload.is_group_representative).to be_nil
    end
  end

  # Each partner encodes the part differently. Missed, every chip on a Stretta set
  # renders the same generic label and the block tells the reader nothing.
  describe '#part_name' do
    it 'reads SMD parts off the title suffix' do
      score = build(:score, :smd, title: 'Birds of a Feather (arr. Holmes) - Trombone 2')
      expect(score.part_name).to eq('Trombone 2')
    end

    it 'reads Stretta parts off the stored itemtype' do
      score = build(:score, :stretta, title: 'Hymne', group_key: 'g',
                                      stretta_metadata: { 'itemtype' => 'Violine 1 (Orchesterstimme)' })
      expect(score.part_name).to eq('Violine 1 (Orchesterstimme)')
    end
  end

  describe '#purchasable?' do
    it 'requires a commercial source and external_id' do
      expect(build(:score, :smd).purchasable?).to be true
      expect(build(:score, source: 'smd', external_id: nil).purchasable?).to be false
      expect(build(:score, :pdmx).purchasable?).to be false
    end

    # SMD never sets available_for_sale (always nil) — only an explicit false,
    # which only Stretta ever writes, may hide the buy button.
    it 'excludes a delisted Stretta product but not an SMD row with no signal' do
      expect(build(:score, :stretta, available_for_sale: false).purchasable?).to be false
      expect(build(:score, :stretta, available_for_sale: true).purchasable?).to be true
      expect(build(:score, :smd, available_for_sale: nil).purchasable?).to be true
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
      full_score = create(:score, :smd, title: 'Test - Full Score', group_key: group_key, is_group_representative: true)
      create(:score, :smd, title: 'Test - Trumpet 1', group_key: group_key, is_group_representative: false)
      solo = create(:score, :smd, title: 'Solo Product', group_key: nil)

      result = Score.where(source: 'smd').deduplicate_arrangements
      expect(result).to include(full_score, solo)
      expect(result.count).to eq(2)
    end
  end

  describe '#group_representative' do
    let(:group_key) { 'crazy train|hl-123' }

    it 'returns the active representative for a hidden member' do
      rep = create(:score, :smd, title: 'Crazy Train - Full Score', group_key: group_key, is_group_representative: true)
      member = create(:score, :smd, title: 'Crazy Train - Trombone 2', group_key: group_key, is_group_representative: false)

      expect(member.group_representative).to eq(rep)
    end

    it 'treats a NULL is_group_representative as a hidden member' do
      rep = create(:score, :smd, title: 'Crazy Train - Full Score', group_key: group_key, is_group_representative: true)
      member = create(:score, :smd, title: 'Crazy Train - Bass', group_key: group_key, is_group_representative: nil)

      expect(member.group_representative).to eq(rep)
    end

    it 'returns nil for the representative itself' do
      rep = create(:score, :smd, title: 'Crazy Train - Full Score', group_key: group_key, is_group_representative: true)

      expect(rep.group_representative).to be_nil
    end

    it 'returns nil for an SMD ungrouped score' do
      ungrouped = create(:score, :smd, title: 'Solo Product', group_key: nil)

      expect(ungrouped.group_representative).to be_nil
    end

    it 'returns nil for a free (non-SMD) score' do
      free = create(:score, title: 'Locus Iste')

      expect(free.group_representative).to be_nil
    end

    it 'returns nil when no active representative exists (deleted rep)' do
      create(:score, :smd, title: 'Crazy Train - Full Score', group_key: group_key,
             is_group_representative: true, deleted_at: Time.current)
      member = create(:score, :smd, title: 'Crazy Train - Trombone 2', group_key: group_key, is_group_representative: false)

      expect(member.group_representative).to be_nil
    end
  end

  describe '#professional_editions' do
    let(:free) { create(:score, title: 'Locus Iste', composer: 'Bruckner, Anton') }

    it 'orders by rank and hides soft-deleted and suppressed targets' do
      visible = create(:score, :smd)
      deleted = create(:score, :smd, deleted_at: Time.current)
      suppressed = create(:score, :smd)
      later = create(:score, :smd)
      ScoreSmdMatch.create!(score: free, smd_score: later, rank: 2)
      ScoreSmdMatch.create!(score: free, smd_score: visible, rank: 1)
      ScoreSmdMatch.create!(score: free, smd_score: deleted, rank: 3)
      ScoreSmdMatch.create!(score: free, smd_score: suppressed, rank: 3, suppressed: true)

      expect(free.professional_editions).to eq([ visible, later ])
    end

    it 'deletes match rows in both directions when a score is destroyed' do
      target = create(:score, :smd)
      ScoreSmdMatch.create!(score: free, smd_score: target, rank: 1)

      target.destroy!

      expect(ScoreSmdMatch.count).to eq(0)
    end
  end

  describe "hub filter scopes" do
    it "accepts the slug the hub dropdown emits" do
      score = create(:score, genre: "Art Song", genre_status: "normalized")
      expect(Score.by_genre("art-song")).to include(score)
    end

    it "does not treat a flute as a lute" do
      flute = create(:score, instruments: "Alto Flute, Piano")
      lute  = create(:score, instruments: "Lute, Flute")
      expect(Score.by_instrument("lute")).to include(lute)
      expect(Score.by_instrument("lute")).not_to include(flute)
    end

    it "still matches an instrument named inside a longer part" do
      score = create(:score, instruments: "Violoncello, Piano")
      expect(Score.by_instrument("cello")).to include(score)
    end
  end
end
