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
end
