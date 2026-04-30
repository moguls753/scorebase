require "rails_helper"

RSpec.describe SmartSearchFeedback, type: :model do
  it "validates verdict inclusion" do
    record = build(:smart_search_feedback, verdict: "weird")
    expect(record).not_to be_valid
    expect(record.errors[:verdict]).to be_present
  end

  it "requires ip_hash" do
    record = build(:smart_search_feedback, ip_hash: nil)
    expect(record).not_to be_valid
    expect(record.errors[:ip_hash]).to include("can't be blank")
  end

  it "rejects comment over 1000 chars" do
    record = build(:smart_search_feedback, comment: "x" * 1001)
    expect(record).not_to be_valid
  end

  it "rejects a second feedback from the same ip_hash on the same query" do
    query = create(:smart_search_query)
    hash  = Digest::SHA256.hexdigest("test|same")
    create(:smart_search_feedback, smart_search_query: query, ip_hash: hash)
    duplicate = build(:smart_search_feedback, smart_search_query: query, ip_hash: hash)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:ip_hash]).to include("already voted on this query")
  end

  it "rejects a duplicate (query, ip_hash) at the DB level when validation is bypassed" do
    query = create(:smart_search_query)
    hash  = Digest::SHA256.hexdigest("test|same")
    create(:smart_search_feedback, smart_search_query: query, ip_hash: hash)
    duplicate = build(:smart_search_feedback, smart_search_query: query, ip_hash: hash)
    expect { duplicate.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "allows two different ip_hashes to vote on the same query" do
    query = create(:smart_search_query)
    create(:smart_search_feedback, smart_search_query: query, ip_hash: Digest::SHA256.hexdigest("test|alice"))
    second = build(:smart_search_feedback,    smart_search_query: query, ip_hash: Digest::SHA256.hexdigest("test|bob"))
    expect(second).to be_valid
  end
end
