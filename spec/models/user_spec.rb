require 'rails_helper'

RSpec.describe User, type: :model do
  describe '#pro?' do
    let(:user) { create(:user) }

    context 'when subscribed_until is nil' do
      it 'returns false' do
        user.subscribed_until = nil
        expect(user.pro?).to be false
      end
    end

    context 'when subscribed_until is in the past' do
      it 'returns false' do
        user.subscribed_until = 1.day.ago
        expect(user.pro?).to be false
      end
    end

    context 'when subscribed_until is in the future' do
      it 'returns true' do
        user.subscribed_until = 1.day.from_now
        expect(user.pro?).to be true
      end
    end

    context 'when subscribed_until is exactly now' do
      it 'returns false' do
        user.subscribed_until = Time.current
        expect(user.pro?).to be false
      end
    end
  end

  describe 'search limits' do
    describe '#search_limit' do
      it 'returns FREE_SEARCH_LIMIT for non-pro users' do
        user = create(:user)
        expect(user.search_limit).to eq(User::FREE_SEARCH_LIMIT)
      end

      it 'returns PRO_MONTHLY_LIMIT for pro users' do
        user = create(:user, :pro)
        expect(user.search_limit).to eq(User::PRO_MONTHLY_LIMIT)
      end
    end

    describe '#searches_remaining' do
      it 'returns full limit for new users' do
        user = create(:user)
        expect(user.searches_remaining).to eq(User::FREE_SEARCH_LIMIT)
      end

      it 'decreases as searches are used' do
        user = create(:user, smart_search_count: 2)
        expect(user.searches_remaining).to eq(1)
      end

      it 'returns 0 when limit exhausted' do
        user = create(:user, smart_search_count: 5)
        expect(user.searches_remaining).to eq(0)
      end
    end

    describe '#can_smart_search?' do
      it 'returns true when searches remaining' do
        user = create(:user)
        expect(user.can_smart_search?).to be true
      end

      it 'returns false when limit exhausted' do
        user = create(:user, smart_search_count: 3)
        expect(user.can_smart_search?).to be false
      end
    end

    describe '#use_smart_search!' do
      it 'increments the count' do
        user = create(:user)
        expect { user.use_smart_search! }.to change { user.smart_search_count }.by(1)
      end
    end

    describe '#ensure_monthly_reset!' do
      it 'resets count at start of new month for pro users' do
        user = create(:user, :pro, smart_search_count: 50, search_count_reset_at: 1.month.ago)

        user.ensure_monthly_reset!

        expect(user.smart_search_count).to eq(0)
        expect(user.searches_remaining).to eq(User::PRO_MONTHLY_LIMIT)
      end

      it 'does not reset within same month' do
        user = create(:user, :pro, smart_search_count: 50, search_count_reset_at: Time.current.beginning_of_month)

        user.ensure_monthly_reset!

        expect(user.smart_search_count).to eq(50)
        expect(user.searches_remaining).to eq(User::PRO_MONTHLY_LIMIT - 50)
      end

      it 'does not reset for free users' do
        user = create(:user, smart_search_count: 3)

        user.ensure_monthly_reset!

        expect(user.smart_search_count).to eq(3)
        expect(user.searches_remaining).to eq(0)
      end
    end
  end
end
