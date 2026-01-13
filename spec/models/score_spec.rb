require 'rails_helper'

RSpec.describe Score do
  describe 'validations' do
    it { should validate_presence_of(:title) }
    it { should validate_presence_of(:data_path) }
    it { should validate_uniqueness_of(:data_path) }
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
end
