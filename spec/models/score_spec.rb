require 'rails_helper'

RSpec.describe Score do
  describe 'validations' do
    it { should validate_presence_of(:title) }
    it { should validate_presence_of(:data_path) }
    it { should validate_uniqueness_of(:data_path) }
    it { should validate_inclusion_of(:source).in_array(Score::SOURCES).allow_nil }
  end

  describe 'factory' do
    it 'creates a valid score' do
      score = build(:score)
      expect(score).to be_valid
    end
  end

  describe 'scopes' do
    describe '.by_source' do
      let!(:pdmx_score) { create(:score, source: 'pdmx') }
      let!(:cpdl_score) { create(:score, :cpdl) }

      it 'filters by source' do
        expect(Score.by_source('pdmx')).to include(pdmx_score)
        expect(Score.by_source('pdmx')).not_to include(cpdl_score)
      end
    end

    describe '.search' do
      let!(:bach_score) { create(:score, title: 'Mass in B minor', composer: 'Bach') }
      let!(:mozart_score) { create(:score, title: 'Requiem', composer: 'Mozart') }

      it 'searches by title' do
        expect(Score.search('Mass')).to include(bach_score)
        expect(Score.search('Mass')).not_to include(mozart_score)
      end

      it 'searches by composer' do
        expect(Score.search('Mozart')).to include(mozart_score)
        expect(Score.search('Mozart')).not_to include(bach_score)
      end
    end
  end

  describe '#source helpers' do
    it 'identifies pdmx source' do
      score = build(:score, source: 'pdmx')
      expect(score.pdmx?).to be true
      expect(score.external?).to be false
    end

    it 'identifies cpdl as external' do
      score = build(:score, :cpdl)
      expect(score.cpdl?).to be true
      expect(score.external?).to be true
    end
  end
end
