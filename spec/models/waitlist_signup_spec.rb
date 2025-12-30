require "rails_helper"

RSpec.describe WaitlistSignup, type: :model do
  # Test what matters: email normalization and uniqueness
  describe "email normalization" do
    it "downcases email addresses" do
      signup = WaitlistSignup.create!(email: "USER@EXAMPLE.COM", locale: "en")
      expect(signup.email).to eq("user@example.com")
    end

    it "strips whitespace" do
      signup = WaitlistSignup.create!(email: "  user@example.com  ", locale: "en")
      expect(signup.email).to eq("user@example.com")
    end

    it "prevents duplicate emails regardless of case" do
      WaitlistSignup.create!(email: "user@example.com", locale: "en")
      duplicate = WaitlistSignup.new(email: "USER@EXAMPLE.COM", locale: "en")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to include("has already been taken")
    end
  end

  # Test validation basics
  it "requires a valid email format" do
    invalid = WaitlistSignup.new(email: "not-an-email", locale: "en")
    expect(invalid).not_to be_valid
  end

  it "requires a locale" do
    no_locale = WaitlistSignup.new(email: "test@example.com", locale: nil)
    expect(no_locale).not_to be_valid
  end

  it "only allows en or de locales" do
    invalid = WaitlistSignup.new(email: "test@example.com", locale: "fr")
    expect(invalid).not_to be_valid
  end
end
